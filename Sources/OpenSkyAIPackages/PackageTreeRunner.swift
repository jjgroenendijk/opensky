// Runs a package's procedure tree: which procedures run now, and what runs after one
// ends. Branch rules from the Creation Kit wiki page "Category:Package Templates":
// a sequence runs its children in order, a stacked branch its first valid child, a
// random branch one valid child, and a simultaneous branch all of them until one ends.

import OpenSkyConditions
import OpenSkyFormatsESM

/// What the runner asks of the session: branch conditions and leaf setups.
@MainActor
public protocol PackageTreeHost {
    mutating func passes(_ conditions: [Condition]) -> Bool
    func setup(for leaf: PackageProcedureLeaf, objectLists: [Int8: [ReferenceKey]])
        -> PackageLeafSetup
}

/// A command from one running procedure.
nonisolated public struct PackageTreeCommand: Equatable, Sendable {
    public let leaf: Int
    public let command: PackageProcedureCommand
}

nonisolated public struct PackageRunningLeaf: Equatable, Sendable {
    public let leaf: PackageProcedureLeaf
    public internal(set) var machine: PackageProcedureMachine
    public let setup: PackageLeafSetup
}

nonisolated public struct PackageTreeRunner: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case succeeded
        case failed
    }

    enum Entry: Equatable {
        case running
        case succeeded
        case failed
        case skipped
    }

    public let tree: PackageProcedureTree
    /// The procedures running now, by leaf node.
    public internal(set) var running: [Int: PackageRunningLeaf] = [:]
    /// The leaf whose walk the mover runs.
    public internal(set) var mover: Int?
    /// What finds found, by the object-list input they fill.
    public internal(set) var objectLists: [Int8: [ReferenceKey]] = [:]
    /// Times the package was done: a `FNAM` procedure succeeded or the tree ran out.
    public internal(set) var completions = 0
    /// Set once the tree stopped for good.
    public internal(set) var outcome: Outcome?
    /// The last procedure that ended, for the readout once nothing runs.
    public internal(set) var lastFinished: PackageProcedureMachine?
    var cursors: [Int: Int] = [:]
    var live: [Int: Set<Int>] = [:]
    var random: ConditionRandom
    var commands: [PackageTreeCommand] = []

    public init(tree: PackageProcedureTree, seed: UInt64) {
        self.tree = tree
        random = ConditionRandom(seed: seed)
    }

    /// The machine the readout shows: the walking one, else any running one.
    public var primary: PackageProcedureMachine? {
        if let mover, let leaf = running[mover] {
            return leaf.machine
        }
        return running.keys.min().flatMap { running[$0]?.machine } ?? lastFinished
    }

    /// Repeatable patrol laps and orbits so far, each of which ends the package once.
    public var laps: Int {
        running.values.reduce(0) { $0 + $1.machine.laps }
    }

    @MainActor
    public mutating func start(host: inout some PackageTreeHost) -> [PackageTreeCommand] {
        guard running.isEmpty, outcome == nil, !tree.nodes.isEmpty else { return [] }
        let entry = enter(0, host: &host)
        if entry != .running {
            rootEnded(success: entry == .succeeded, host: &host, restarts: false)
        }
        return drain()
    }

    /// Feeds one event to one running procedure, then moves the tree on.
    @MainActor
    public mutating func handle(
        _ event: PackageProcedureEvent, leaf node: Int, host: inout some PackageTreeHost
    ) -> [PackageTreeCommand] {
        guard var leaf = running[node] else { return [] }
        let produced = leaf.machine.handle(event)
        running[node] = leaf
        collect(produced, from: node)
        settle(node, host: &host)
        return drain()
    }

    /// The running leaves, in node order, so a tick visits them deterministically.
    public var runningNodes: [Int] {
        running.keys.sorted()
    }

    public var runningMachines: [PackageProcedureMachine] {
        runningNodes.compactMap { running[$0]?.machine }
    }

    @MainActor
    mutating func enter(_ node: Int, host: inout some PackageTreeHost) -> Entry {
        let entry = tree.nodes[node]
        guard entry.conditions.isEmpty || host.passes(entry.conditions) else { return .skipped }
        switch entry.content {
        case let .procedure(leaf):
            return enterLeaf(leaf, host: &host)
        case .branch(.sequence):
            return advanceSequence(node, from: 0, host: &host)
        case .branch(.stacked):
            for (offset, child) in entry.children.enumerated() {
                cursors[node] = offset
                let result = enter(child, host: &host)
                if result != .skipped {
                    return result
                }
            }
            return .failed
        case .branch(.random):
            return enterRandom(node, host: &host)
        case .branch(.simultaneous):
            return enterSimultaneous(node, host: &host)
        }
    }

    @MainActor
    private mutating func enterLeaf(
        _ leaf: PackageProcedureLeaf, host: inout some PackageTreeHost
    ) -> Entry {
        let setup = host.setup(for: leaf, objectLists: objectLists)
        var machine = PackageProcedureMachine(setup: setup.setup)
        let produced = machine.start()
        running[leaf.node] = PackageRunningLeaf(leaf: leaf, machine: machine, setup: setup)
        collect(produced, from: leaf.node)
        guard let success = finished(leaf.node) else { return .running }
        retire(leaf.node)
        if success, leaf.completesPackage {
            completePackage()
        }
        return success ? .succeeded : .failed
    }

    @MainActor
    mutating func advanceSequence(
        _ node: Int, from first: Int, host: inout some PackageTreeHost
    ) -> Entry {
        let children = tree.nodes[node].children
        var offset = first
        while offset < children.count, outcome == nil {
            cursors[node] = offset
            switch enter(children[offset], host: &host) {
            case .running: return .running
            case .failed: return .failed
            case .succeeded, .skipped: offset += 1
            }
        }
        return .succeeded
    }

    @MainActor
    private mutating func enterRandom(_ node: Int, host: inout some PackageTreeHost) -> Entry {
        let valid = tree.nodes[node].children.filter {
            let conditions = tree.nodes[$0].conditions
            return conditions.isEmpty || host.passes(conditions)
        }
        guard !valid.isEmpty else { return .failed }
        let pick = valid[Int(random.next() % UInt64(valid.count))]
        return enter(pick, host: &host)
    }

    @MainActor
    private mutating func enterSimultaneous(
        _ node: Int, host: inout some PackageTreeHost
    ) -> Entry {
        live[node] = []
        for child in tree.nodes[node].children {
            switch enter(child, host: &host) {
            case .running:
                live[node, default: []].insert(child)
            case .succeeded:
                stopSubtree(of: node)
                return .succeeded
            case .failed, .skipped:
                continue
            }
            if outcome != nil {
                return .succeeded
            }
        }
        return live[node]?.isEmpty == false ? .running : .failed
    }

    mutating func collect(_ produced: [PackageProcedureCommand], from node: Int) {
        for command in produced {
            if case .move = command {
                mover = node
            }
            commands.append(PackageTreeCommand(leaf: node, command: command))
        }
    }

    private mutating func drain() -> [PackageTreeCommand] {
        defer { commands = [] }
        return commands
    }
}
