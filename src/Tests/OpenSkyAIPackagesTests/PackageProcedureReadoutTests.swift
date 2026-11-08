// The AI readout's procedure line: where a held patrol is along its markers.

@testable import OpenSkyAIPackages
import OpenSkyWorldInterface
import simd
import Testing

struct PackageProcedureReadoutTests {
    @Test func aPatrolCountsItsMarkersFromOne() {
        var machine = PackageProcedureMachine(
            kind: .patrol, center: .zero, destination: SIMD3(1, 0, 0), radius: 0,
            path: [SIMD3(2, 0, 0), SIMD3(3, 0, 0)], seed: 1
        )
        _ = machine.start()
        #expect(AIPackageReadout
            .procedureStateText(for: machine) == "Procedure: patrol, moving, point 1 of 3")
        _ = machine.handle(.arrived)
        #expect(AIPackageReadout
            .procedureStateText(for: machine) == "Procedure: patrol, moving, point 2 of 3")
        _ = machine.handle(.movementFailed)
        #expect(AIPackageReadout
            .procedureStateText(for: machine) == "Procedure: patrol, failed, point 2 of 3")
    }

    @Test func aTravelHasNoPoints() {
        var machine = PackageProcedureMachine(kind: .travel, center: .zero, radius: 0, seed: 1)
        _ = machine.start()
        #expect(AIPackageReadout.procedureStateText(for: machine) == "Procedure: travel, moving")
    }
}

struct PackageRunningReadoutTests {
    @Test func proceduresThatRunTogetherAreListed() {
        var sit = PackageProcedureMachine(kind: .sit, center: .zero, radius: 0, seed: 1)
        var wait = PackageProcedureMachine(kind: .wait, center: .zero, radius: 0, seed: 1)
        _ = sit.start()
        _ = wait.start()
        #expect(AIPackageReadout.runningText(for: [sit]) == nil)
        #expect(AIPackageReadout.runningText(for: [sit, wait])
            == "Running: sit (moving), wait (waiting)")
    }
}
