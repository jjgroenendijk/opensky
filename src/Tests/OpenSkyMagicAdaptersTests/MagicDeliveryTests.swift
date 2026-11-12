// The delivery and effect parts aim spells, pick targets, and run the coordinator's commands.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicAdapters
@testable import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkySessionTesting
import OpenSkyWorldInterface
import Testing

@MainActor
struct MagicDeliveryTests {
    private let host = MagicHost()
    private let loop = FakeCombatLoopRuntimePort()
    private var adapter: MagicWorldAdapter {
        MagicWorldAdapter(game: host)
    }

    private static let foe = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let friend = ReferenceKey.plugin(name: "base.esm", objectID: 0x21)
    private static let payload = SpellPayload(
        spell: .plugin(name: "base.esm", objectID: 0x600), sourcePlugin: "base.esm",
        caster: .player,
        entries: [], isHostile: true, ignoresResistance: false, projectile: nil, name: "Flames"
    )

    init() {
        host.fakeCombat.loop = loop
        host.fakeCombat.meleeAttackerValue = MeleeAttacker(key: .player, feet: .zero, facing: 0)
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.foe, feet: SIMD3(100, 0, 0)),
            CombatActorObservation(key: Self.friend, feet: SIMD3(0, 100, 0))
        ]
    }

    @Test func thePlayersCloakReachesHostileActorsInRange() {
        host.fakeFactions.hostilityResult = .hostile
        #expect(adapter.cloakTargets(around: .player, radius: 150).count == 2)
        #expect(adapter.cloakTargets(around: .player, radius: 50).isEmpty)
        #expect(adapter.cloakTargets(around: Self.foe, radius: 150) == [.player])
        host.fakeFactions.hostilityResult = .neutral
        #expect(adapter.cloakTargets(around: Self.foe, radius: 150).isEmpty)
    }

    @Test func aStaggerOnThePlayerRunsThroughTheGraph() {
        host.fakeCombat.raiseCombatEventResult = true
        #expect(adapter.staggerActor(.player, magnitude: 0.5))
        #expect(host.fakeCombat.writeCombatVariableCalls.count == 1)
        #expect(adapter.staggerActor(Self.foe, magnitude: 0.5))
        #expect(loop.noteStaggerCalls == [Self.foe])
    }

    @Test func runesWaitForHostileLivingActors() {
        host.fakeCombat.projectileTargetsResult = [
            MeleeTarget(key: Self.foe, feet: .zero), MeleeTarget(key: Self.friend, feet: .zero)
        ]
        host.fakeFactions.hostilityResult = .hostile
        #expect(adapter.runeTriggers(for: .player).count == 2)
        #expect(adapter.runeTriggers(for: Self.foe).map(\.key) == [.player])
        #expect(adapter.spellHitCandidates().count == 3)
        host.fakeFactions.hostilityResult = .neutral
        #expect(adapter.runeTriggers(for: Self.foe).isEmpty)
    }

    @Test func aSpellWithoutAProjectileHasNoReachOrProximity() {
        #expect(!adapter.fireSpellProjectile(Self.payload))
        #expect(adapter.projectileProximity(of: Self.payload) == 0)
        #expect(adapter.castReach(within: 0) >= 0)
        adapter.knock([Self.foe], awayFrom: .player, by: Self.payload)
        #expect(host.fakeEffectsWorld.knockDownActorCalls.isEmpty)
    }

    @Test func facingAndSightAnswerTrueForAnUnknownActor() {
        let stranger = ReferenceKey.plugin(name: "base.esm", objectID: 0x99)
        #expect(adapter.actor(stranger, faces: .player))
        #expect(adapter.point(.zero, canSee: stranger))
        #expect(adapter.actor(Self.foe, faces: .player) == adapter.actor(Self.foe, faces: .player))
    }

    @Test func aClearLineSeesTheActor() {
        #expect(adapter.point(SIMD3(500, 0, 0), canSee: Self.foe))
        #expect(host.fakeCombat.sweepProjectileCalls.count == 1)
    }

    @Test func withoutRecordsNoKeywordMatches() {
        let holder = ActorValueHolder(key: Self.foe, subject: .actor(base: FormID(0x30)))
        #expect(adapter.keyword(editorID: "ActorTypeNPC") == nil)
        #expect(!adapter.actorHasKeyword("ActorTypeNPC", on: holder))
        #expect(!adapter.itemHasKeyword("ArmorHeavy", on: FormID(0x40)))
        #expect(adapter.isOutdoors)
    }

    @Test func eachCommandReachesTheSystemThatShowsIt() {
        host.fakeEffectsWorld.placeAtMeResult = Self.foe
        adapter.archetypeEffects.run([
            .notice("Too heavy"),
            .stagger(Self.foe, magnitude: 1),
            .spawnHazard(Self.friend, at: Self.foe),
            .playerShouted(words: 2)
        ])
        #expect(host.fakeHUD.showNotificationCalls == ["Too heavy"])
        #expect(loop.noteStaggerCalls == [Self.foe])
        #expect(host.fakeEffectsWorld.placeAtMeCalls.count == 1)
        #expect(host.fakeStoryWorld.commentOnPlayerCalls.count == 1)
        #expect(host.fakeControllerRumble.shoutCalls == [2])
    }

    @Test func aHitFromOutsideRunsItsCommandsAtOnce() {
        host.fakeMagic.applySpellHitResult = SpellHitReport()
        host.fakeMagic.frameStep.takeCommandsResult = [.notice("Hit")]
        _ = adapter.applySpellHit(SpellHit(payload: Self.payload, targets: []))
        #expect(host.fakeMagic.applySpellHitCalls.count == 1)
        #expect(host.fakeHUD.showNotificationCalls == ["Hit"])
    }

    @Test func onlyTheRidingPlayerIsOnAFlyingMount() {
        #expect(!adapter.isOnFlyingMount(.player))
        host.fakeMountWorld.flyingMounts = [Self.foe]
        #expect(adapter.isOnFlyingMount(.player))
        #expect(!adapter.isOnFlyingMount(Self.foe))
        adapter.forgetPickpocketCatch(of: Self.foe)
        #expect(host.fakeInventoryWorld.forgetPickpocketCatchCalls == [Self.foe])
        adapter.noteSpellCast(Self.foe, by: .player)
        #expect(adapter.shoutCooldown(recovery: 10, multiplier: 1) > 0)
    }
}
