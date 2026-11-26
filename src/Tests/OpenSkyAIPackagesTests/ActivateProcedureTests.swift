// The Activate procedure: it counts "Number to Activate" across a repeating tree, waits
// out the activate action at an ordinary target, and sits in a furniture target.
// docs/engine/activate-procedure.md. Synthetic branches only.

@testable import OpenSkyAIPackages
import OpenSkyConditions
@testable import OpenSkyFormatsESM
import OpenSkyWorldInterface
import OpenSkyWorldTesting
import simd
import Testing

/// Gives every Activate leaf one target, the count, and a seat when it is furniture.
@MainActor
private struct ActivateHost: PackageTreeHost {
    let count: Int
    let furniture: Bool

    func passes(_: [Condition]) -> Bool {
        true
    }

    func setup(
        for leaf: PackageProcedureLeaf, objectLists _: [Int8: [ReferenceKey]]
    ) -> PackageLeafSetup {
        var setup = PackageProcedureSetup(
            kind: leaf.kind, center: .zero, destination: SIMD3(100, 0, 0)
        )
        setup.targets = [ActivateProcedureTests.rail]
        setup.activationCount = count
        setup.countInput = 2
        setup.sitsInTarget = furniture
        return PackageLeafSetup(setup: setup, seat: furniture ? Self.seat : nil)
    }

    static let seat = PackageSeat(
        furniture: ActivateProcedureTests.rail, index: 0,
        seat: FurnitureSeat(position: [100, 0, 0], heading: 0, animationType: 1, keyword: nil)
    )
}

/// Names the rail for any target, and gives it a seat only when it is furniture.
@MainActor
private struct RailResolver: PackageInputResolving {
    let furniture: Bool

    func place(of _: Package.Location) -> PackagePlace? {
        nil
    }

    func reference(of _: Package.Target) -> ReferenceKey? {
        ActivateProcedureTests.rail
    }

    func position(of _: ReferenceKey) -> SIMD3<Float>? {
        SIMD3(100, 0, 0)
    }

    func patrolPath(from _: Package.Target) -> [SIMD3<Float>]? {
        nil
    }

    func seat(in _: ReferenceKey, animation _: UInt16) -> PackageSeat? {
        furniture ? ActivateHost.seat : nil
    }
}

@MainActor
struct ActivateProcedureTests {
    static let rail = PackageRuntimeFixture.key(0x950)

    /// `ActivateSpecialFurniture`: a repeating Sequence round one Activate.
    private static func runner() throws -> PackageTreeRunner {
        try PackageTreeRunner(
            tree: PackageProcedureTree(branches: [
                PackageDetails.Branch(type: "Sequence", branchCount: 1, rootFlags: 1),
                PackageDetails.Branch(
                    type: "Procedure", conditionList: ConditionList(), procedureType: "Activate",
                    successCompletesPackage: false, dataInputIndexes: [0, 2]
                )
            ]),
            seed: 3
        )
    }

    private static func commands(_ tagged: [PackageTreeCommand]) -> [PackageProcedureCommand] {
        tagged.map(\.command)
    }

    @Test func aRepeatingTreeActivatesOnceForACountOfOne() throws {
        var host = ActivateHost(count: 1, furniture: false)
        var runner = try Self.runner()
        #expect(Self.commands(runner.start(host: &host)) == [.move(to: SIMD3(100, 0, 0))])
        #expect(runner.handle(.arrived, leaf: 1, host: &host).isEmpty, "the action plays first")
        #expect(runner.handle(.tick(0.5), leaf: 1, host: &host).isEmpty)
        #expect(Self.commands(runner.handle(.tick(0.5), leaf: 1, host: &host)) == [
            .act(.activate(Self.rail))
        ])
        let after = runner.handle(.acted(.done), leaf: 1, host: &host)
        #expect(after.isEmpty, "the tree starts again, and the spent count ends it at once")
        #expect(runner.outcome == .succeeded)
        #expect(runner.running.isEmpty)
    }

    @Test func aRefusedActivationStillCounts() throws {
        var host = ActivateHost(count: 1, furniture: false)
        var runner = try Self.runner()
        _ = runner.start(host: &host)
        _ = runner.handle(.arrived, leaf: 1, host: &host)
        _ = runner.handle(.tick(1), leaf: 1, host: &host)
        _ = runner.handle(.acted(.failed), leaf: 1, host: &host)
        #expect(runner.outcome == .succeeded)
    }

    @Test func aFurnitureTargetIsUsedAndTheProcedureEndsOnceSeated() throws {
        var host = ActivateHost(count: 1, furniture: true)
        var runner = try Self.runner()
        _ = runner.start(host: &host)
        let seated = Self.commands(runner.handle(.arrived, leaf: 1, host: &host))
        #expect(seated == [.sit])
        #expect(runner.outcome == .succeeded)
        #expect(runner.finishedSeats[1] == ActivateHost.seat)
    }

    @Test func aCountOfTwoWalksBackForTheSecondActivation() {
        var setup = PackageProcedureSetup(kind: .activate, center: .zero, destination: [100, 0, 0])
        setup.targets = [Self.rail]
        setup.activationCount = 2
        var machine = PackageProcedureMachine(setup: setup)
        _ = machine.start()
        _ = machine.handle(.arrived)
        _ = machine.handle(.tick(1))
        #expect(machine.handle(.acted(.done)) == [.move(to: [100, 0, 0])])
        _ = machine.handle(.arrived)
        _ = machine.handle(.tick(1))
        _ = machine.handle(.acted(.done))
        #expect(machine.state == .complete)
        #expect(machine.activations == 2)
    }

    @Test func aCountOfZeroDoesNothing() {
        var setup = PackageProcedureSetup(kind: .activate, center: .zero, destination: [100, 0, 0])
        setup.targets = [Self.rail]
        setup.activationCount = 0
        var machine = PackageProcedureMachine(setup: setup)
        #expect(machine.start().isEmpty)
        #expect(machine.state == .complete)
    }

    @Test func numberToActivateIsTheSecondParameter() {
        #expect(PackageProcedureParameters.table[.activate]?.count == 1)
    }

    private static func inputs(count: Package.DataValue, furniture: Bool) -> PackageLeafSetup {
        PackageProcedureInputs(
            leaf: PackageProcedureLeaf(node: 1, kind: .activate, inputIndexes: [0, 2]),
            values: [
                0: .target(Package.Target(rawKind: 0, value: 0x950, countOrDistance: 0)),
                2: count
            ],
            objectLists: [:], start: .zero, seed: 1
        ).build(resolver: RailResolver(furniture: furniture))
    }

    @Test func theInputsSetTheCountAndTheSeatOfAFurnitureTarget() {
        let rail = Self.inputs(count: .integer(2), furniture: false)
        #expect(rail.setup.activationCount == 2)
        #expect(rail.setup.countInput == 2)
        #expect(!rail.setup.sitsInTarget)
        let bench = Self.inputs(count: .integer(1), furniture: true)
        #expect(bench.setup.sitsInTarget)
        #expect(bench.seat == ActivateHost.seat)
        #expect(!Self.inputs(count: .integer(0), furniture: true).setup.sitsInTarget)
    }
}
