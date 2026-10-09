// The AI panel's procedure line: where a held patrol is along its markers.

@testable import OpenSkyWorld
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
            .procedureStateText(for: machine) == "Procedure: moving, point 1 of 3")
        _ = machine.handle(.arrived)
        #expect(AIPackageReadout
            .procedureStateText(for: machine) == "Procedure: moving, point 2 of 3")
        _ = machine.handle(.movementFailed)
        #expect(AIPackageReadout
            .procedureStateText(for: machine) == "Procedure: failed, point 2 of 3")
    }

    @Test func aTravelHasNoPoints() {
        var machine = PackageProcedureMachine(kind: .travel, center: .zero, radius: 0, seed: 1)
        _ = machine.start()
        #expect(AIPackageReadout.procedureStateText(for: machine) == "Procedure: moving")
    }
}
