// The melee runtime end to end: a hit-frame event drives a sweep that hits a
// target capsule, damage matches WEAP data, blocking reduces it, and a swing
// through two targets hits each once. The graph is stood in for by the event
// names it would fire; `MeleeCombatRealDataTests` uses the vanilla graph.

@testable import OpenSkyActorsInterface
@testable import OpenSkyBehavior
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyMagicInterface
@testable import OpenSkyPhysics
import simd
import Testing

@MainActor
struct MeleeCombatRuntimeTests {
    @Test func aHitFrameSweepsAndDamagesTheTargetByTheWeaponsBaseDamage() {
        let world = FakeMeleeWorld()
        world.targets = [MeleeTarget(key: .generated(1), feet: SIMD3(80, 0, 0))]
        let runtime = Self.runtime(world: world, damage: 24)

        Self.drawAndSwing(runtime)

        #expect(runtime.hitCount == 1)
        #expect(runtime.swingCount == 1)
        #expect(world.damage == [.generated(1): 24])
        #expect(runtime.trace.last?.damage.applied == 24)
    }

    @Test func aSwingThroughTwoOverlappingTargetsHitsEachOnce() {
        let world = FakeMeleeWorld()
        world.targets = [
            MeleeTarget(key: .generated(1), feet: SIMD3(80, 0, 0)),
            MeleeTarget(key: .generated(2), feet: SIMD3(96, 0, 0))
        ]
        let runtime = Self.runtime(world: world, damage: 10)

        Self.drawAndSwing(runtime)

        #expect(runtime.hitCount == 2)
        #expect(world.damage == [.generated(1): 10, .generated(2): 10])
    }

    @Test func twoHitFramesInOneSwingStillLandOneHitPerTarget() {
        let world = FakeMeleeWorld()
        world.targets = [MeleeTarget(key: .generated(1), feet: SIMD3(80, 0, 0))]
        let runtime = Self.runtime(world: world, damage: 10)

        runtime.handleGraphEvents(Self.drawEvents)
        runtime.acceptFrame(MeleeIntent(attack: true))
        // The census shows `2_HitFrame` beside `HitFrame`; a graph that fires
        // the contact annotation twice must not land two hits. Two guards stop
        // it and this pins both: the phase guard refuses a second contact from
        // a swing already in `contact`, and the once-per-swing set would refuse
        // the target even if the phase let it through.
        runtime.handleGraphEvents([
            CombatGraphNames.attackStart,
            CombatGraphNames.hitFrame,
            CombatGraphNames.hitFrame
        ])

        #expect(runtime.swingCount == 1)
        #expect(runtime.hitCount == 1)
    }

    @Test func theNextSwingCanHitTheSameTargetAgain() {
        let world = FakeMeleeWorld()
        world.targets = [MeleeTarget(key: .generated(1), feet: SIMD3(80, 0, 0))]
        let runtime = Self.runtime(world: world, damage: 10)

        Self.drawAndSwing(runtime)
        runtime.handleGraphEvents([CombatGraphNames.attackStop])
        Self.swing(runtime)

        #expect(runtime.hitCount == 2)
        #expect(world.damage == [.generated(1): 20])
    }

    @Test func blockingReducesTheDamageByThePinnedFormula() {
        let world = FakeMeleeWorld()
        world.targets = [MeleeTarget(key: .player, feet: SIMD3(80, 0, 0))]
        world.blocks = [.player: .weapon]
        let runtime = Self.runtime(world: world, damage: 10, attacker: .generated(7))

        Self.drawAndSwing(runtime)

        // 0.3 + 0.2 * 10 * (1 + 15 * 2 / 100) / 100 = 0.326
        let applied = world.damage[.player] ?? 0
        #expect(abs(applied - 10 * (1 - 0.326)) < 0.001)
        #expect(runtime.trace.last?.damage.wasBlocked == true)
    }

    @Test func aSwingWithTheWeaponSheathedResolvesNothing() {
        let world = FakeMeleeWorld()
        world.targets = [MeleeTarget(key: .generated(1), feet: SIMD3(80, 0, 0))]
        let runtime = Self.runtime(world: world, damage: 10)

        runtime.acceptFrame(MeleeIntent(attack: true))

        #expect(world.raised.contains(CombatGraphNames.attackStart) == false)
        #expect(runtime.hitCount == 0)
    }

    @Test func theDrawToggleRaisesTheCensusNamedEventInBothDirections() {
        let world = FakeMeleeWorld()
        let runtime = Self.runtime(world: world, damage: 10)

        // Two events per request, in this order: the intent the
        // player expressed, then the equip event `0_master.hkx` transitions on.
        runtime.acceptFrame(MeleeIntent(toggleWeaponDrawn: true))
        #expect(
            world.raised.suffix(2)
                == [CombatGraphNames.weaponDraw, CombatGraphNames.weapEquip]
        )

        runtime.handleGraphEvents(Self.drawEvents)
        runtime.acceptFrame(MeleeIntent(toggleWeaponDrawn: true))
        #expect(
            world.raised.suffix(2)
                == [CombatGraphNames.weaponSheathe, CombatGraphNames.unequip]
        )
    }

    @Test func drawingASpellRaisesTheMagicEquipInsteadOfTheWeaponOne() {
        let world = FakeMeleeWorld()
        let runtime = Self.runtime(world: world, damage: 10)
        runtime.weapon = MeleeWeaponProfile(damage: 10, reach: 1, handType: .spell)

        runtime.acceptFrame(MeleeIntent(toggleWeaponDrawn: true))

        #expect(world.raised.contains(CombatGraphNames.magicEquip))
        #expect(!world.raised.contains(CombatGraphNames.weapEquip))
    }

    @Test func bothHandTypesArePublishedToTheGraphVariables() {
        let world = FakeMeleeWorld()
        let runtime = Self.runtime(world: world, damage: 10)
        runtime.weapon = MeleeWeaponProfile(damage: 10, reach: 1, handType: .mace)
        runtime.offHand = .shield

        runtime.acceptFrame(MeleeIntent())

        #expect(world.variables[CombatGraphNames.rightHandType] == .int(4))
        #expect(world.variables[CombatGraphNames.leftHandType] == .int(10))
    }

    @Test func theHandTypesAreWrittenBeforeTheEquipEventIsRaised() {
        let world = FakeMeleeWorld()
        let runtime = Self.runtime(world: world, damage: 10)
        runtime.weapon = MeleeWeaponProfile(damage: 10, reach: 1, handType: .bow)

        runtime.acceptFrame(MeleeIntent(toggleWeaponDrawn: true))

        // The graph selects the equip clip off `iRightHandType` when it acts on
        // `WeapEquip`, so a frame that equips and draws at once must write the
        // number first or the previous weapon's clip plays.
        #expect(world.writesBeforeFirstRaise.contains(CombatGraphNames.rightHandType))
    }

    @Test func blockRaisesOnItsEdgesOnly() {
        let world = FakeMeleeWorld()
        let runtime = Self.runtime(world: world, damage: 10)

        runtime.acceptFrame(MeleeIntent(block: true))
        runtime.acceptFrame(MeleeIntent(block: true))
        runtime.acceptFrame(MeleeIntent(block: false))

        let blockEvents = world.raised.filter {
            $0 == CombatGraphNames.blockStart || $0 == CombatGraphNames.blockStop
        }
        #expect(blockEvents == [CombatGraphNames.blockStart, CombatGraphNames.blockStop])
    }

    @Test func aStaggeringWeaponRaisesStaggerOnTheTargetsGraph() {
        let world = FakeMeleeWorld()
        world.targets = [MeleeTarget(key: .player, feet: SIMD3(80, 0, 0))]
        // The attacker must not be `.player`, which is `.generated(0)`: a
        // swing never hits its own owner.
        let runtime = Self.runtime(
            world: world, damage: 10, stagger: 0.75, attacker: .generated(7)
        )

        Self.drawAndSwing(runtime)

        #expect(world.raisedOnTarget[.player]?.contains(CombatGraphNames.staggerStart) == true)
        #expect(world.variables[CombatGraphNames.staggerMagnitude] == .real(0.75))
        #expect(runtime.trace.last?.staggered == true)
    }

    @Test func aWeaponWithNoStaggerDoesNotRaiseOne() {
        let world = FakeMeleeWorld()
        world.targets = [MeleeTarget(key: .generated(1), feet: SIMD3(80, 0, 0))]
        let runtime = Self.runtime(world: world, damage: 10, stagger: 0)

        Self.drawAndSwing(runtime)

        #expect(runtime.trace.last?.staggered == false)
    }

    @Test func attackStateIsPublishedToTheGraphVariables() {
        let world = FakeMeleeWorld()
        let runtime = Self.runtime(world: world, damage: 10)

        runtime.handleGraphEvents(Self.drawEvents)
        runtime.handleGraphEvents([CombatGraphNames.attackStart])
        #expect(world.variables[CombatGraphNames.isAttacking] == .bool(true))

        runtime.handleGraphEvents([CombatGraphNames.attackStop])
        #expect(world.variables[CombatGraphNames.isAttacking] == .bool(false))
    }

    @Test func resetForgetsTheSwingAndTheTrace() {
        let world = FakeMeleeWorld()
        world.targets = [MeleeTarget(key: .generated(1), feet: SIMD3(80, 0, 0))]
        let runtime = Self.runtime(world: world, damage: 10)
        Self.drawAndSwing(runtime)

        runtime.reset()

        #expect(runtime.trace.isEmpty)
        #expect(runtime.hitCount == 0)
        #expect(runtime.state.drawState == .sheathed)
    }

    // MARK: - Fixture

    /// Draw, then one full swing.
    private static let drawEvents = [
        CombatGraphNames.weaponDraw,
        CombatGraphNames.beginWeaponDraw
    ]

    private static func runtime(
        world: FakeMeleeWorld,
        damage: Float,
        stagger: Float = 0,
        attacker: ReferenceKey = .generated(0)
    ) -> MeleeCombatRuntime {
        world.attacker = MeleeAttacker(key: attacker, feet: SIMD3<Float>(), facing: 0)
        let runtime = MeleeCombatRuntime(settings: .synthetic, world: world)
        runtime.weapon = MeleeWeaponProfile(damage: damage, reach: 1, stagger: stagger)
        return runtime
    }

    private static func drawAndSwing(_ runtime: MeleeCombatRuntime) {
        runtime.handleGraphEvents(drawEvents)
        swing(runtime)
    }

    private static func swing(_ runtime: MeleeCombatRuntime) {
        runtime.acceptFrame(MeleeIntent(attack: true))
        runtime.handleGraphEvents([
            CombatGraphNames.attackStart,
            CombatGraphNames.preHitFrame,
            CombatGraphNames.hitFrame
        ])
    }
}
