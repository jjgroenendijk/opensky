// The pure readout rules behind the locomotion and first-person panels.

@testable import OpenSkyBehavior
@testable import OpenSkyWorld
import simd
import Testing

struct PlayerCoreTests {
    @Test
    func everyBindingIsListedWithItsLiveState() {
        let rows = PlayerCore.bindings(run: true, sprint: false, sneak: true, airborne: false)
        #expect(rows.map(\.label) == ["Run", "Sprint", "Sneak", "Jump"])
        #expect(rows.map(\.isActive) == [true, false, true, false])
    }

    @Test
    func anUndeclaredVariableIsListedWithNoValue() {
        let rows = PlayerCore.variables(of: nil)
        #expect(rows.map(\.name).suffix(3) == [
            LocomotionGraphNames.isFirstPerson,
            LocomotionGraphNames.firstPersonInt,
            LocomotionGraphNames.firstPersonReal
        ])
        #expect(rows.count == LocomotionGraphNames.variables.count + 3)
        #expect(rows.allSatisfy { $0.value == nil })
    }

    @Test
    func valuesAreFormattedByTheirGraphType() {
        #expect(PlayerCore.describe(.bool(true)) == "true")
        #expect(PlayerCore.describe(.int(7)) == "7")
        #expect(PlayerCore.describe(.real(0.5)) == "0.500")
        #expect(PlayerCore.describe(.quad(SIMD4(1, 2, 3, 4))) == "1.000, 2.000, 3.000, 4.000")
    }

    @Test
    func noRigDropsNoPieces() {
        #expect(PlayerCore.droppedPieceCount(of: nil) == 0)
    }
}
