// Melee combos: an attack press during a swing waits for the clip's combo window
// (`AttackWinStart` to `AttackWinEnd`) and then chains into the next swing.
// See docs/engine/melee-combat.md, "Combos".

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPhysics
import simd
import Testing

@MainActor
struct MeleeComboTests {
    @Test func theComboWindowReadsAsTheNextAttackAfterContact() {
        var state = Self.drawnState()
        state.handle(CombatGraphNames.attackStart)
        state.handle(CombatGraphNames.hitFrame)
        state.endFrame()
        #expect(state.actionFacts.attackState == .followThrough)

        state.handle(CombatGraphNames.attackWinStart)
        #expect(state.isChainWindowOpen)
        #expect(state.actionFacts.attackState == .nextAttack)

        state.handle(CombatGraphNames.attackWinEnd)
        #expect(!state.isChainWindowOpen)
        #expect(state.actionFacts.attackState == .followThrough)
    }

    @Test func aChainedStartBeginsANewSwingAndClosesTheWindow() {
        var state = Self.drawnState()
        state.handle(CombatGraphNames.attackStart)
        state.handle(CombatGraphNames.attackWinStart)
        let first = state.swingID

        state.handle(CombatGraphNames.attackStart)

        #expect(state.attackPhase == .windup)
        #expect(state.swingID == first + 1)
        #expect(!state.isChainWindowOpen)
    }

    @Test func onlyASwingHasAComboWindow() {
        var state = Self.drawnState()
        #expect(state.handle(CombatGraphNames.attackWinStart) == nil)
        state.handle(CombatGraphNames.attackStart)
        state.handle(CombatGraphNames.attackWinStart)

        state.handle(CombatGraphNames.attackStop)

        #expect(!state.isChainWindowOpen)
    }

    @Test func aPressMidSwingWaitsForTheWindowThenChains() {
        let world = FakeMeleeWorld()
        let runtime = Self.swinging(world: world)

        runtime.acceptFrame(MeleeIntent(attack: true))
        #expect(Self.starts(world) == 1)

        runtime.handleGraphEvents([CombatGraphNames.attackWinStart])
        runtime.acceptFrame(MeleeIntent())
        #expect(Self.starts(world) == 2)
    }

    @Test func aPressInTheWindowChainsAtOnce() {
        let world = FakeMeleeWorld()
        let runtime = Self.swinging(world: world)
        runtime.handleGraphEvents([CombatGraphNames.attackWinStart])

        runtime.acceptFrame(MeleeIntent(attack: true))

        #expect(Self.starts(world) == 2)
    }

    @Test func aPressWithNoWindowIsDroppedWhenTheSwingEnds() {
        let world = FakeMeleeWorld()
        let runtime = Self.swinging(world: world)
        runtime.acceptFrame(MeleeIntent(attack: true))

        runtime.handleGraphEvents([CombatGraphNames.attackStop])
        runtime.acceptFrame(MeleeIntent())
        runtime.handleGraphEvents([CombatGraphNames.attackWinStart])
        runtime.acceptFrame(MeleeIntent())

        #expect(Self.starts(world) == 1)
        #expect(runtime.state.attackPhase == .idle)
    }

    @Test func theChainedSwingCanHitTheSameTargetAgain() {
        let world = FakeMeleeWorld()
        world.targets = [MeleeTarget(key: .generated(1), feet: SIMD3(80, 0, 0))]
        let runtime = Self.swinging(world: world)
        runtime.handleGraphEvents([CombatGraphNames.hitFrame, CombatGraphNames.attackWinStart])

        runtime.acceptFrame(MeleeIntent(attack: true))
        runtime.handleGraphEvents([CombatGraphNames.attackStart, CombatGraphNames.hitFrame])

        #expect(runtime.hitCount == 2)
    }

    // MARK: - Fixture

    private static func drawnState() -> MeleeCombatState {
        var state = MeleeCombatState()
        state.handle(MeleeCombatRuntimeTests.drawEvents)
        return state
    }

    /// A drawn weapon with one swing started by a tap.
    private static func swinging(world: FakeMeleeWorld) -> MeleeCombatRuntime {
        let runtime = MeleeCombatRuntimeTests.runtime(world: world, damage: 10)
        runtime.handleGraphEvents(MeleeCombatRuntimeTests.drawEvents)
        runtime.acceptFrame(MeleeIntent(attack: true))
        runtime.handleGraphEvents([CombatGraphNames.attackStart])
        return runtime
    }

    private static func starts(_ world: FakeMeleeWorld) -> Int {
        world.raised.filter { $0 == CombatGraphNames.attackStart }.count
    }
}
