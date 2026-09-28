// The melee state machine (issue #195, roadmap item 15.4): draw and sheath
// follow the clip annotations, the attack phase follows the events the graph
// fires back, and a stagger takes the swing away.
//
// Every name here comes from the M14 behavior census over the install
// (`logs/hkx-behavior-census.log`); the fixture is a list of strings, which is
// exactly what the queue hands a consumer.

@testable import opensky
import Testing

struct MeleeCombatStateTests {
    @Test func drawingMovesTheAttachmentOnTheClipAnnotationNotTheRequest() {
        var state = MeleeCombatState()

        let requested = state.handle(CombatGraphNames.weaponDraw)
        #expect(requested?.drawState == .drawing)
        // The weapon is still sheathed while the hand reaches for it.
        #expect(state.drawState.isWeaponInHand == false)
        #expect(requested?.movedAttachment == false)

        let moved = state.handle(CombatGraphNames.beginWeaponDraw)
        #expect(moved?.drawState == .drawn)
        #expect(moved?.movedAttachment == true)
        #expect(state.drawState.isWeaponInHand)
    }

    @Test func sheathingKeepsTheWeaponInHandUntilTheAnnotation() {
        var state = MeleeCombatState()
        state.handle(CombatGraphNames.weaponDraw)
        state.handle(CombatGraphNames.beginWeaponDraw)

        state.handle(CombatGraphNames.weaponSheathe)
        #expect(state.drawState == .sheathing)
        #expect(state.drawState.isWeaponInHand)

        let moved = state.handle(CombatGraphNames.beginWeaponSheathe)
        #expect(moved?.movedAttachment == true)
        #expect(state.drawState == .sheathed)
    }

    /// Five of the vanilla equip clips carry no `BeginWeaponDraw` at all, so
    /// the graph's own end-of-equip transition has to move the state too
    /// (issue #403).
    @Test func theGraphsOwnEquipTransitionAlsoReportsTheWeaponInHand() {
        var state = MeleeCombatState()
        state.handle(CombatGraphNames.weaponDraw)

        let moved = state.handle(CombatGraphNames.weapEquipOut)
        #expect(moved?.drawState == .drawn)
        #expect(moved?.movedAttachment == true)

        state.handle(CombatGraphNames.weaponSheathe)
        let sheathed = state.handle(CombatGraphNames.unequipOut)
        #expect(sheathed?.drawState == .sheathed)
        #expect(sheathed?.movedAttachment == true)
    }

    /// The annotation is the early one and the transition the late one, so a
    /// clip that fires both must move the attachment exactly once.
    @Test func aClipThatFiresBothDrawEventsMovesTheAttachmentOnce() {
        var state = MeleeCombatState()
        state.handle(CombatGraphNames.weaponDraw)

        #expect(state.handle(CombatGraphNames.beginWeaponDraw)?.movedAttachment == true)
        #expect(state.handle(CombatGraphNames.weapEquipOut)?.movedAttachment == false)
        #expect(state.drawState == .drawn)
    }

    @Test func attackPhaseFollowsTheFiredEvents() {
        var state = drawn()

        #expect(state.handle(CombatGraphNames.attackStart)?.attackPhase == .windup)
        #expect(state.handle(CombatGraphNames.preHitFrame)?.attackPhase == .swinging)

        let contact = state.handle(CombatGraphNames.hitFrame)
        #expect(contact?.attackPhase == .contact)
        #expect(contact?.openedHitWindow == true)
        #expect(state.contactCount == 1)

        state.endFrame()
        #expect(state.attackPhase == .recovery)
        #expect(state.handle(CombatGraphNames.attackStop)?.attackPhase == .idle)
    }

    @Test func aSheathedWeaponCannotStartASwing() {
        var state = MeleeCombatState()
        #expect(state.handle(CombatGraphNames.attackStart) == nil)
        #expect(state.attackPhase == .idle)
        #expect(state.swingID == 0)
    }

    @Test func staggerCancelsTheSwingInFlight() {
        var state = drawn()
        state.handle(CombatGraphNames.attackStart)
        state.handle(CombatGraphNames.preHitFrame)

        state.handle(CombatGraphNames.staggerStart)
        #expect(state.isStaggering)
        #expect(state.attackPhase == .idle)
        // And no new swing starts while the stagger plays.
        #expect(state.handle(CombatGraphNames.attackStart) == nil)

        state.handle(CombatGraphNames.staggerStop)
        #expect(state.handle(CombatGraphNames.attackStart)?.attackPhase == .windup)
    }

    @Test func sheathingCancelsTheSwingInFlight() {
        var state = drawn()
        state.handle(CombatGraphNames.attackStart)

        state.handle(CombatGraphNames.weaponSheathe)
        #expect(state.attackPhase == .idle)
    }

    @Test func blockingTracksItsOwnEdges() {
        var state = drawn()

        #expect(state.handle(CombatGraphNames.blockStart)?.attackPhase == .idle)
        #expect(state.isBlocking)
        // A repeated start is not an edge and reports no change.
        #expect(state.handle(CombatGraphNames.blockStart) == nil)

        state.handle(CombatGraphNames.blockStop)
        #expect(state.isBlocking == false)
        #expect(state.handle(CombatGraphNames.blockStop) == nil)
    }

    @Test func eachSwingGetsItsOwnIdentity() {
        var state = drawn()
        state.handle([
            CombatGraphNames.attackStart,
            CombatGraphNames.hitFrame,
            CombatGraphNames.attackStop
        ])
        let first = state.swingID
        state.handle([CombatGraphNames.attackStart, CombatGraphNames.hitFrame])

        #expect(state.swingID == first + 1)
        #expect(state.contactCount == 2)
    }

    @Test func unrecognizedNamesAreDroppedSilently() {
        var state = drawn()
        // Vanilla fires hundreds of names this machine has no business acting
        // on; the footstep tags are the ones it shares a stream with.
        #expect(state.handle("FootLeft") == nil)
        #expect(state.handle("SoundPlay.WPNBlade1HandSmallDraw") == nil)
        #expect(state.drawState == .drawn)
    }

    /// A state with the weapon out, which is what every attack test starts
    /// from.
    private func drawn() -> MeleeCombatState {
        var state = MeleeCombatState()
        state.handle(CombatGraphNames.weaponDraw)
        state.handle(CombatGraphNames.beginWeaponDraw)
        return state
    }
}
