// The combat loop's weapon draw: when an NPC draws and sheathes, what its graph hears, and
// what holds the draw. Shared setup is in `CombatLoopFixture`.

@testable import OpenSkyActorsInterface
import OpenSkyBehavior
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyPerceptionInterface
import simd
import Testing

@MainActor
struct CombatLoopWeaponDrawTests {
    private typealias Fixture = CombatLoopFixture

    @Test func anNPCDrawsWhenItsFightStartsAndSheathesWhenItEnds() {
        let (runtime, world) = Fixture.session()
        #expect(runtime.drawState(of: Fixture.opponent) == .sheathed)
        #expect(runtime.drawState(of: .player) == nil)
        Fixture.engage(runtime, world)
        Self.step(runtime, while: .sheathed)
        #expect(runtime.drawState(of: Fixture.opponent) == .drawing)
        Fixture.run(runtime, seconds: 1)
        #expect(runtime.drawState(of: Fixture.opponent) == .drawn)
        // A calmed actor does not pick the fight up again, as a stopped one would.
        runtime.setHostility(.neutral, on: Fixture.opponent)
        Self.step(runtime, while: .drawn)
        #expect(runtime.drawState(of: Fixture.opponent) == .sheathing)
        Fixture.run(runtime, seconds: 1)
        #expect(runtime.drawState(of: Fixture.opponent) == .sheathed)
        #expect(runtime.weaponDraws.isEmpty)
        // The actor's graph hears the draw, with its hands, and the sheathe.
        let events = world.actorEvents.filter { $0.key == Fixture.opponent }.map(\.name)
            .filter { [CombatGraphNames.weapEquip, CombatGraphNames.unequip].contains($0) }
        #expect(events == [CombatGraphNames.weapEquip, CombatGraphNames.unequip])
        let hands = world.actorVariables[Fixture.opponent]
        #expect(
            hands?[CombatGraphNames.rightHandType]
                == world.combatWeapon(of: Fixture.opponent).handType.graphValue
        )
        #expect(hands?[CombatGraphNames.leftHandType] == CombatHandType.shield.graphValue)
    }

    @Test func aDeadActorsGraphHearsNoSheathe() {
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: 1)
        #expect(runtime.drawState(of: Fixture.opponent) == .drawn)
        world.kill(Fixture.opponent)
        Fixture.run(runtime, seconds: 1)
        #expect(runtime.weaponDraws[Fixture.opponent] == nil)
        let names = world.actorEvents.filter { $0.key == Fixture.opponent }.map(\.name)
        #expect(!names.contains(CombatGraphNames.unequip))
    }

    @Test func anEmptyLeftHandIsZeroToTheGraph() {
        let (runtime, world) = Fixture.session()
        world.shieldless = [Fixture.opponent]
        Fixture.engage(runtime, world)
        Self.step(runtime, while: .sheathed)
        #expect(world.actorVariables[Fixture.opponent]?[CombatGraphNames.leftHandType] == .int(0))
    }

    /// The graph's equip clip outlasts the draw timer; the actor holds its attack until it ends.
    @Test func aGraphStillEquippingHoldsTheDrawAndEveryAttack() {
        let (runtime, world) = Fixture.session()
        world.equipping = [Fixture.opponent]
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: 1.5)
        #expect(runtime.drawState(of: Fixture.opponent) == .drawing)
        #expect(runtime.behaviors[Fixture.opponent]?.attackCount == 0)
        world.equipping = []
        Fixture.run(runtime, seconds: 3)
        #expect(runtime.drawState(of: Fixture.opponent) == .drawn)
        #expect(runtime.behaviors[Fixture.opponent]?.attackCount ?? 0 > 0)
    }

    /// A sheathe would pull the attacker's graph out of the paired clip.
    @Test func aKillMoveKeepsTheWeaponOutAfterTheFightEnds() {
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: 1)
        world.inKillMove = [Fixture.opponent]
        runtime.setHostility(.neutral, on: Fixture.opponent)
        Fixture.run(runtime, seconds: 1)
        #expect(runtime.drawState(of: Fixture.opponent) == .drawn)
        world.inKillMove = []
        Fixture.run(runtime, seconds: 1)
        #expect(runtime.drawState(of: Fixture.opponent) != .drawn)
    }

    /// The game starts an attack only from a graph state that reports `IsAttackReady`.
    @Test func aGraphNotReadyToAttackHoldsEveryAttack() {
        let (runtime, world) = Fixture.session()
        world.notAttackReady = [Fixture.opponent]
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: 3)
        #expect(runtime.drawState(of: Fixture.opponent) == .drawn)
        #expect(runtime.behaviors[Fixture.opponent]?.attackCount == 0)
        world.notAttackReady = []
        Fixture.run(runtime, seconds: 3)
        #expect(runtime.behaviors[Fixture.opponent]?.attackCount ?? 0 > 0)
    }

    /// A graph stuck in its equip clip holds the draw for a bounded time only.
    @Test func aStuckEquipClipCannotStopTheFight() {
        var draw = NPCWeaponDraw()
        let step: Float = 0.1
        draw.advance(wantsDrawn: true, by: step, graphEquipping: true)
        let limit = NPCWeaponDraw.transitionSeconds + NPCWeaponDraw.longestGraphHoldSeconds
        for _ in 0 ..< Int(limit / step) - 2 {
            draw.advance(wantsDrawn: true, by: step, graphEquipping: true)
        }
        #expect(draw.state == .drawing)
        for _ in 0 ..< 4 {
            draw.advance(wantsDrawn: true, by: step, graphEquipping: true)
        }
        #expect(draw.state == .drawn)
    }

    /// Steps for at most two seconds while the opponent's weapon stays `state`.
    private static func step(_ runtime: CombatLoopRuntime, while state: WeaponDrawState) {
        for _ in 0 ..< 120 where runtime.drawState(of: Fixture.opponent) == state {
            Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds)
        }
    }
}
