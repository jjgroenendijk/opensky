// The left hand's weapon: the block button attacks with it, both buttons together
// strike with both weapons, and each strike picks its own kill-move action.

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyPhysics
import simd
import Testing

@MainActor
struct MeleeLeftHandTests {
    private static let target = ReferenceKey.generated(1)

    private static func armed(_ world: FakeMeleeWorld) -> MeleeCombatRuntime {
        world.targets = [MeleeTarget(key: target, feet: SIMD3(80, 0, 0))]
        world.stamina = 500
        let runtime = MeleeCombatRuntimeTests.runtime(world: world, damage: 10)
        runtime.weapon = MeleeWeaponProfile(damage: 10, reach: 1, handType: .sword, weight: 10)
        runtime.leftWeapon = MeleeWeaponProfile(damage: 4, reach: 1, handType: .dagger, weight: 2)
        runtime.handleGraphEvents(MeleeCombatRuntimeTests.drawEvents)
        return runtime
    }

    @Test func theLeftButtonSwingsTheLeftWeapon() {
        let world = FakeMeleeWorld()
        let runtime = Self.armed(world)

        runtime.acceptFrame(MeleeIntent(deltaTime: 0.05, leftAttackHeld: true))
        runtime.acceptFrame(MeleeIntent(deltaTime: 0.05))
        runtime.handleGraphEvents([CombatGraphNames.attackStartLeftHand, CombatGraphNames.hitFrame])

        #expect(world.raised.contains(CombatGraphNames.attackStartLeftHand))
        #expect(!world.raised.contains(CombatGraphNames.blockStart))
        #expect(runtime.strikeHand == .left)
        #expect(world.damage == [Self.target: 4])
    }

    @Test func aHeldLeftPressPowersUpByDirection() {
        let world = FakeMeleeWorld()
        let runtime = Self.armed(world)

        runtime.acceptFrame(MeleeIntent(deltaTime: 0.1, moveForward: 1, leftAttackHeld: true))
        runtime.acceptFrame(MeleeIntent(deltaTime: 0.25, moveForward: 1, leftAttackHeld: true))

        #expect(world.raised.contains(CombatGraphNames.attackPowerStartForwardLeftHand))
        // (20 + 2) * 2 for the 2-weight dagger.
        #expect(world.staminaPaid == [44])
    }

    @Test func bothButtonsTogetherStrikeWithBothWeapons() {
        let world = FakeMeleeWorld()
        let runtime = Self.armed(world)

        runtime.acceptFrame(MeleeIntent(attack: true, attackHeld: true, deltaTime: 0.02))
        runtime.acceptFrame(MeleeIntent(attackHeld: true, deltaTime: 0.02, leftAttackHeld: true))
        runtime.acceptFrame(MeleeIntent(deltaTime: 0.02))
        let hits = runtime.handleGraphEvents([
            CombatGraphNames.attackStartDualWield, CombatGraphNames.hitFrame
        ])

        #expect(world.raised.contains(CombatGraphNames.attackStartDualWield))
        #expect(runtime.strikeHand == .dual)
        #expect(hits.map(\.damage.applied) == [10, 4])
        #expect(world.damage == [Self.target: 14])
    }

    @Test func aDualHoldPaysForBothWeapons() {
        let world = FakeMeleeWorld()
        let runtime = Self.armed(world)

        runtime.acceptFrame(MeleeIntent(attack: true, attackHeld: true, deltaTime: 0.02))
        runtime.acceptFrame(MeleeIntent(attackHeld: true, deltaTime: 0.3, leftAttackHeld: true))

        #expect(world.raised.contains(CombatGraphNames.attackPowerStartDualWield))
        #expect(world.staminaPaid == [60 + 44])
    }

    @Test func aLatePressOfTheOtherHandIsDropped() {
        let world = FakeMeleeWorld()
        let runtime = Self.armed(world)

        runtime.acceptFrame(MeleeIntent(attack: true, attackHeld: true, deltaTime: 0.2))
        runtime.acceptFrame(MeleeIntent(deltaTime: 0.02, leftAttackHeld: true))

        #expect(world.raised.contains(CombatGraphNames.attackStart))
        #expect(!world.raised.contains(CombatGraphNames.attackStartDualWield))
        #expect(runtime.strikeHand == .right)
    }

    @Test func withoutALeftWeaponTheLeftButtonDoesNothing() {
        let world = FakeMeleeWorld()
        let runtime = Self.armed(world)
        runtime.leftWeapon = nil

        runtime.acceptFrame(MeleeIntent(deltaTime: 0.05, leftAttackHeld: true))
        runtime.acceptFrame(MeleeIntent(deltaTime: 0.05))

        #expect(!world.raised.contains(CombatGraphNames.attackStartLeftHand))
        #expect(runtime.canStrikeDual == false)
    }

    @Test func aKillingLeftStrikeAsksForTheLeftKillMove() {
        let world = FakeMeleeWorld()
        world.playsKillMoves = true
        let runtime = Self.armed(world)

        runtime.acceptFrame(MeleeIntent(deltaTime: 0.05, leftAttackHeld: true))
        runtime.acceptFrame(MeleeIntent(deltaTime: 0.05))

        #expect(world.killMoveActions == ["ActionLeftAttack"])
        #expect(!world.raised.contains(CombatGraphNames.attackStartLeftHand))
    }

    @Test func eachHandAndPowerHasItsKillMoveAction() {
        #expect(KillMoveAttempt.action(hand: .right, power: false) == "ActionRightAttack")
        #expect(KillMoveAttempt.action(hand: .right, power: true) == "ActionRightPowerAttack")
        #expect(KillMoveAttempt.action(hand: .left, power: true) == "ActionLeftPowerAttack")
        #expect(KillMoveAttempt.action(hand: .dual, power: false) == "ActionDualAttack")
        #expect(KillMoveAttempt.action(hand: .dual, power: true) == "ActionDualPowerAttack")
    }

    @Test func everyDirectionHasALeftHandPowerEvent() {
        let directions: [MeleePowerDirection] = [.inPlace, .forward, .backward, .left, .right]
        let names = Set(directions.map(\.leftHandEventName))
        #expect(names.count == 5)
        #expect(names.isSubset(of: CombatGraphNames.strikeStarts))
        #expect(MeleePowerDirection.backward.leftHandEventName == "attackPowerStartBackLeftHand")
    }
}
