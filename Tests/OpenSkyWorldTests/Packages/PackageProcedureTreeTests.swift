// The procedure tree read from a flat branch list, and the runner's branch rules:
// sequence, stacked, random, simultaneous, repeat, `FNAM`, and find output.
// Synthetic branches only.

import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import simd
import Testing

/// Passes every condition but the marker one, and walks each leaf to its node index.
@MainActor
private struct FakeTreeHost: PackageTreeHost {
    static let failing: UInt16 = 999

    func passes(_ conditions: [Condition]) -> Bool {
        !conditions.contains { $0.functionIndex == Self.failing }
    }

    func setup(
        for leaf: PackageProcedureLeaf, objectLists: [Int8: [ReferenceKey]]
    ) -> PackageLeafSetup {
        var setup = PackageProcedureSetup(
            kind: leaf.kind, center: .zero, destination: SIMD3(Float(leaf.node), 0, 0)
        )
        setup.selector = Package.Target(rawKind: 2, value: 10, countOrDistance: 0)
        let list = leaf.inputIndexes.first.flatMap(\.self)
        setup.targets = list.flatMap { objectLists[$0] } ?? []
        return PackageLeafSetup(setup: setup)
    }
}

@MainActor
struct PackageProcedureTreeTests {
    static let item = PackageRuntimeFixture.key(0x900)

    static func procedure(
        _ name: String, inputs: [UInt8] = [], completes: Bool = false, fails: Bool = false
    ) throws -> PackageDetails.Branch {
        try PackageDetails.Branch(
            type: "Procedure", conditionList: conditions(fails: fails), procedureType: name,
            successCompletesPackage: completes, dataInputIndexes: inputs
        )
    }

    static func branch(
        _ type: String, children: UInt32, repeats: Bool = false
    ) -> PackageDetails.Branch {
        PackageDetails.Branch(type: type, branchCount: children, rootFlags: repeats ? 1 : 0)
    }

    private static func conditions(fails: Bool) throws -> ConditionList {
        var list = ConditionList()
        if fails {
            let marker = ConditionEvaluatorFixture.field(functionIndex: FakeTreeHost.failing)
            try list.decode(field: marker)
        }
        return list
    }

    private static func runner(_ branches: [PackageDetails.Branch]) throws -> PackageTreeRunner {
        try PackageTreeRunner(tree: PackageProcedureTree(branches: branches), seed: 7)
    }

    @Test func aFlatListBuildsItsTreeInPreOrder() throws {
        let tree = try PackageProcedureTree(branches: [
            Self.branch("Sequence", children: 2),
            Self.procedure("Travel", inputs: [0, 0xFF]),
            Self.branch("Stacked", children: 2),
            Self.procedure("Sit"),
            Self.procedure("Wait")
        ])
        #expect(tree.nodes.map(\.children) == [[1, 2], [], [3, 4], [], []])
        #expect(tree.nodes.map(\.parent) == [nil, 0, 0, 2, 2])
        #expect(tree.leaves.map(\.kind) == [.travel, .sit, .wait])
        #expect(tree.leaves.first?.inputIndexes == [0, nil])
    }

    @Test func aMalformedListThrows() throws {
        #expect(throws: PackageTreeError.truncated(branch: 0)) {
            try PackageProcedureTree(branches: [
                Self.branch("Sequence", children: 2),
                Self.procedure("Travel")
            ])
        }
        #expect(throws: PackageTreeError.trailingBranches(count: 1)) {
            try PackageProcedureTree(branches: [
                Self.procedure("Travel"),
                Self.procedure("Wait")
            ])
        }
        #expect(throws: PackageTreeError.unknownBranchType("Loop")) {
            try PackageProcedureTree(branches: [Self.branch("Loop", children: 0)])
        }
    }

    @Test func aSequenceRunsItsChildrenInOrder() throws {
        var runner = try Self.runner([
            Self.branch("Sequence", children: 2),
            Self.procedure("Travel"),
            Self.procedure("Travel", completes: true)
        ])
        var host = FakeTreeHost()
        #expect(runner.start(host: &host) == [.init(leaf: 1, command: .move(to: SIMD3(1, 0, 0)))])
        #expect(runner.handle(.arrived, leaf: 1, host: &host)
            == [.init(leaf: 2, command: .move(to: SIMD3(2, 0, 0)))])
        _ = runner.handle(.arrived, leaf: 2, host: &host)
        #expect(runner.outcome == .succeeded)
        #expect(runner.completions == 1)
    }

    @Test func aStackedBranchRunsItsFirstValidChild() throws {
        var runner = try Self.runner([
            Self.branch("Stacked", children: 2),
            Self.procedure("Travel", fails: true),
            Self.procedure("Wait")
        ])
        var host = FakeTreeHost()
        _ = runner.start(host: &host)
        #expect(runner.runningNodes == [2])
    }

    @Test func aRandomBranchPicksOnlyAValidChild() throws {
        for seed: UInt64 in 0 ..< 8 {
            var runner = try PackageTreeRunner(tree: PackageProcedureTree(branches: [
                Self.branch("Random", children: 2),
                Self.procedure("Travel", fails: true),
                Self.procedure("Wait")
            ]), seed: seed)
            var host = FakeTreeHost()
            _ = runner.start(host: &host)
            #expect(runner.runningNodes == [2])
        }
    }

    /// A failed child leaves the others running; the first success ends the branch.
    @Test func aSimultaneousBranchEndsWhenOneChildSucceeds() throws {
        var runner = try Self.runner([
            Self.branch("Simultaneous", children: 3),
            Self.procedure("Wait"),
            Self.procedure("Travel"),
            Self.procedure("Travel")
        ])
        var host = FakeTreeHost()
        _ = runner.start(host: &host)
        #expect(runner.runningNodes == [1, 2, 3])
        _ = runner.handle(.movementFailed, leaf: 2, host: &host)
        #expect(runner.runningNodes == [1, 3])
        #expect(runner.outcome == nil)
        _ = runner.handle(.arrived, leaf: 3, host: &host)
        #expect(runner.runningNodes.isEmpty)
        #expect(runner.outcome == .succeeded)
    }

    @Test func aRepeatingRootStartsAgain() throws {
        var runner = try Self.runner([
            Self.branch("Sequence", children: 1, repeats: true),
            Self.procedure("Travel")
        ])
        var host = FakeTreeHost()
        _ = runner.start(host: &host)
        #expect(runner.handle(.arrived, leaf: 1, host: &host)
            == [.init(leaf: 1, command: .move(to: SIMD3(1, 0, 0)))])
        #expect(runner.completions == 1)
        #expect(runner.outcome == nil)
    }

    /// Find fills its output list, and the acquire after it picks up what was found.
    @Test func aFindHandsWhatItFoundToTheNextProcedure() throws {
        var runner = try Self.runner([
            Self.branch("Sequence", children: 2),
            Self.procedure("Find", inputs: [0, 1, 2]),
            Self.procedure("Acquire", inputs: [2], completes: true)
        ])
        var host = FakeTreeHost()
        let find = runner.start(host: &host)
        #expect(find.map(\.leaf) == [1])
        _ = runner.handle(.acted(.found([Self.item])), leaf: 1, host: &host)
        #expect(runner.objectLists[2] == [Self.item])
        #expect(runner.handle(.arrived, leaf: 2, host: &host)
            == [.init(leaf: 2, command: .act(.pickUp(Self.item)))])
        _ = runner.handle(.acted(.done), leaf: 2, host: &host)
        #expect(runner.outcome == .succeeded)
    }
}
