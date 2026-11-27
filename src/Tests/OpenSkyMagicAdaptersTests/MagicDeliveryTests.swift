// The delivery and effect parts aim spells, pick targets, and run the coordinator's commands.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyMagicAdapters
@testable import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyRendering
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

    /// A spell whose projectile record is missing launches nothing.
    @Test func aSpellWithAnUnknownProjectileLaunchesNothing() {
        let payload = SpellPayload(
            spell: Self.payload.spell, sourcePlugin: "base.esm", caster: .player, entries: [],
            isHostile: true, ignoresResistance: false, projectile: FormID(0x7777), name: "Bolt"
        )
        host.fakeCombat.archery = FakeArcheryRuntimePort()
        #expect(!adapter.fireSpellProjectile(payload))
        #expect(adapter.projectileProximity(of: payload) == 0)
    }

    @Test func aNavmeshSnapTakesTheNearestSpot() {
        host.fakeStreamer.navmeshSpotsResult = [SIMD3(4, 0, 0), SIMD3(9, 0, 0)]
        #expect(adapter.navmeshPoint(near: .zero, within: 32) == SIMD3(4, 0, 0))
        #expect(host.fakeStreamer.navmeshSpotsCalls.first?.largeActor == false)
        host.fakeStreamer.navmeshSpotsResult = []
        #expect(adapter.navmeshPoint(near: .zero, within: 32) == nil)
    }

    /// The foe stands east of the player. Its ward covers the player when it looks west.
    @Test func anNPCSpellCarriesTheTrackerNoiseOfItsCastingType() {
        let archery = FakeArcheryRuntimePort()
        archery.projectiles.npcSpellAimResult = SIMD3(0, 0, 50)
        host.fakeCombat.archery = archery
        let delivery = MagicSpellDeliveryAdapter(game: host)
        let npc = ProjectileShooter(
            key: Self.foe, origin: .zero, aim: SIMD3(1, 0, 0), isFirstPerson: false, location: nil
        )
        var concentration = Self.payload
        concentration.isConcentration = true

        let aimed = delivery.aimedWithNoise(npc, casting: concentration)

        #expect(aimed.aim == SIMD3(0, 0, 1))
        #expect(archery.projectiles.npcSpellAimCalls.first?.concentration == true)
        let player = ProjectileShooter(
            key: .player, origin: .zero, aim: SIMD3(1, 0, 0), isFirstPerson: true, location: nil
        )
        #expect(delivery.aimedWithNoise(player, casting: Self.payload).aim == SIMD3(1, 0, 0))
    }

    @Test func aWardFacesAlongTheHoldersHeading() {
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.foe, feet: SIMD3(100, 0, 0), heading: 1.5 * .pi)
        ]
        #expect(adapter.actor(Self.foe, faces: .player))
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.foe, feet: SIMD3(100, 0, 0), heading: 0.5 * .pi)
        ]
        #expect(!adapter.actor(Self.foe, faces: .player))
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

    @Test func anNPCsCastEventsAndFlagsReachItsGraph() {
        adapter.archetypeEffects.run([
            .actorGraphFlag("bWantCastRight", value: true, actor: Self.foe),
            .actorGraphEvent("MRh_SpellAimedStart", actor: Self.foe)
        ])
        #expect(host.fakeActorGraphs.raiseCalls.map(\.event) == ["MRh_SpellAimedStart"])
        #expect(host.fakeActorGraphs.setVariableCalls.map(\.name) == ["bWantCastRight"])
    }

    @Test func aHandsArtGoesToItsMagicNodeAndItsLightToTheHand() throws {
        let effects = FakeEffectsPort()
        effects.recordsValue = EffectRecordStore(plugins: [])
        host.fakeEffectsWorld.effects = effects
        adapter.archetypeEffects.run([
            .castingArt(
                FormID(0x70),
                plugin: "base.esm",
                caster: Self.foe,
                hand: .left,
                starts: true
            ),
            .castingLight(
                FormID(0x71), plugin: "base.esm", caster: Self.foe, hand: .right, starts: true
            )
        ])
        let art = try #require(effects.showCastingArtCalls.first)
        #expect(art.anchor == .node(Self.foe, "NPC L MagicNode [LMag]"))
        #expect(art.shown)
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
