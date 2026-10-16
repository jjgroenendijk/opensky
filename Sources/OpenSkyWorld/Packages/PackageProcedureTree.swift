// A template's procedure tree, rebuilt from its flat branch list. Each branch that
// is not a procedure is followed by `PRCB` branch-count children, in pre-order.
// docs/formats/packages.md#procedure-tree; branch rules on the Creation Kit wiki
// page "Category:Package Templates".

import OpenSkyConditions
import OpenSkyFormatsESM

nonisolated public enum PackageTreeError: Error, Equatable, Sendable {
    /// A branch asks for more children than the list holds.
    case truncated(branch: Int)
    /// Branches remain after the root's last child.
    case trailingBranches(count: Int)
    case unknownBranchType(String)
}

/// One procedure of the tree, with the data input indexes it reads, in parameter order.
nonisolated public struct PackageProcedureLeaf: Equatable, Sendable {
    /// The leaf's node index in the tree.
    public let node: Int
    public let kind: PackageProcedureKind
    /// `PKC2`; 255 means the parameter has no input.
    public let inputIndexes: [Int8?]
    /// `FNAM`: the package is done when this procedure succeeds.
    public let completesPackage: Bool

    public init(
        node: Int, kind: PackageProcedureKind, inputIndexes: [Int8?] = [],
        completesPackage: Bool = false
    ) {
        self.node = node
        self.kind = kind
        self.inputIndexes = inputIndexes
        self.completesPackage = completesPackage
    }
}

nonisolated public struct PackageProcedureTree: Equatable, Sendable {
    public enum Branch: String, Equatable, Sendable {
        /// Runs its children in order and is done after the last.
        case sequence = "Sequence"
        /// Runs the first child whose conditions are true.
        case stacked = "Stacked"
        /// Runs one child with true conditions, picked at random.
        case random = "Random"
        /// Runs every child at once and is done when any child is.
        case simultaneous = "Simultaneous"
    }

    public enum Content: Equatable, Sendable {
        case branch(Branch)
        case procedure(PackageProcedureLeaf)
    }

    public struct Node: Equatable, Sendable {
        public let content: Content
        public let conditions: [Condition]
        /// `PRCB` flag bit 0: start again when done.
        public let repeats: Bool
        public internal(set) var children: [Int] = []
        public let parent: Int?
    }

    /// Node 0 is the root.
    public let nodes: [Node]

    public var leaves: [PackageProcedureLeaf] {
        nodes.compactMap {
            if case let .procedure(leaf) = $0.content {
                return leaf
            }
            return nil
        }
    }

    public init(branches: [PackageDetails.Branch]) throws(PackageTreeError) {
        var builder = Builder(branches: branches)
        try builder.read(parent: nil)
        guard builder.cursor == branches.count else {
            throw .trailingBranches(count: branches.count - builder.cursor)
        }
        nodes = builder.nodes
    }

    /// A one-procedure tree for a package with no branch list, which keeps the
    /// package's own procedure kind.
    public init(single kind: PackageProcedureKind) {
        nodes = [
            Node(
                content: .branch(.sequence),
                conditions: [],
                repeats: false,
                children: [1],
                parent: nil
            ),
            Node(content: .procedure(PackageProcedureLeaf(
                node: 1, kind: kind, completesPackage: true
            )), conditions: [], repeats: false, parent: 0)
        ]
    }

    /// The template's tree, or the one-procedure tree when it has no usable branches.
    public static func of(_ template: Package, fallback: PackageProcedureKind) -> Self {
        guard
            !template.details.branches.isEmpty,
            let tree = try? Self(branches: template.details.branches)
        else { return Self(single: fallback) }
        return tree
    }

    private struct Builder {
        let branches: [PackageDetails.Branch]
        var nodes: [Node] = []
        var cursor = 0

        @discardableResult
        mutating func read(parent: Int?) throws(PackageTreeError) -> Int {
            guard cursor < branches.count else {
                throw .truncated(branch: parent ?? 0)
            }
            let branch = branches[cursor]
            let index = nodes.count
            cursor += 1
            let repeats = (branch.rootFlags ?? 0) & 1 != 0
            if branch.type == "Procedure" {
                let leaf = PackageProcedureLeaf(
                    node: index,
                    kind: PackageProcedureKind(name: branch.procedureType ?? ""),
                    inputIndexes: branch.dataInputIndexes
                        .map { $0 == 0xFF ? nil : Int8(bitPattern: $0) },
                    completesPackage: branch.successCompletesPackage
                )
                nodes.append(Node(
                    content: .procedure(leaf), conditions: branch.conditions,
                    repeats: repeats, parent: parent
                ))
                return index
            }
            guard let kind = Branch(rawValue: branch.type) else {
                throw .unknownBranchType(branch.type)
            }
            nodes.append(Node(
                content: .branch(kind), conditions: branch.conditions,
                repeats: repeats, parent: parent
            ))
            for _ in 0 ..< (branch.branchCount ?? 0) {
                let child = try read(parent: index)
                nodes[index].children.append(child)
            }
            return index
        }
    }
}
