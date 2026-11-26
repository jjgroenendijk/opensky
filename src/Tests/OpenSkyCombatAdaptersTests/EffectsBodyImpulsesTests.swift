// The effects world pushes bodies and actors, and reads water and health, through its ports.

import Foundation
import OpenSkyCombat
import OpenSkyCombatAdapters
import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyPhysics
import OpenSkySessionTesting
import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct EffectsBodyImpulsesTests {
    private let host = CombatHost()
    private let adapter: EffectsWorldAdapter

    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let dead = ReferenceKey.plugin(name: "base.esm", objectID: 0x21)

    init() {
        host.fakeStreamer.dynamicBodiesValue = DynamicBodyWorld()
        adapter = EffectsWorldAdapter(game: host, now: { Date(timeIntervalSince1970: 0) })
    }

    @Test func anEmptyBodyWorldHasNoImpulseBodies() {
        #expect(adapter.impulseBodies().isEmpty)
    }

    @Test func impulseActorsAreThePlayerAndLivingActors() {
        host.fakeHazardWorld.hazardCandidatesResult = [
            MeleeTarget(key: .player, feet: .zero),
            MeleeTarget(key: Self.actor, feet: .zero),
            MeleeTarget(key: Self.dead, feet: .zero)
        ]
        host.fakeActorWorld.combatActorResult = CombatActorObservation(key: Self.actor, feet: .zero)
        #expect(adapter.impulseActors().map(\.key) == [.player, Self.actor, Self.dead])
    }

    @Test func aSplashShowsItsModelWithOrWithoutASound() {
        for weight in [SplashWeight.silent, .heavy] {
            adapter.showSplash(
                SplashEvent(
                    source: Self.actor,
                    position: .zero,
                    model: "splash.nif",
                    weight: weight
                )
            )
        }
        #expect(host.fakeEffects.showModelCalls.count == 2)
    }

    @Test func waterReadsComeFromTheStreamer() {
        host.fakeStreamer.collision.sampleWaterHeightResult = 12
        #expect(adapter.waterHeight(at: SIMD2(1, 2)) == 12)
        #expect(adapter.waterCurrent(at: .zero) == nil)
        #expect(!adapter.isDangerousWater(at: .zero))
        adapter.waterContacts([])
    }

    @Test func withoutRaceRecordsAnActorIsAPushableMediumBody() {
        #expect(adapter.race(of: Self.actor) == nil)
        #expect(adapter.raceSize(of: Self.actor) == 1)
        #expect(adapter.isPushable(Self.actor))
        _ = adapter.waterPushRace(of: Self.actor)
    }

    @Test func healthAndDamageGoThroughCombat() {
        host.fakeCombatWorld.healthResult = (current: 40, maximum: 100)
        host.fakeCombat.applyHealthDamageResult = true
        #expect(adapter.actorHealth(of: Self.actor)?.current == 40)
        #expect(adapter.applyPhysicsDamage(5, to: Self.actor))
        #expect(host.fakeCombat.applyHealthDamageCalls.count == 1)
    }

    @Test func aKnockDownUsesTheRagdollFirst() {
        #expect(!adapter.knockDown(Self.actor, from: .zero, magnitude: 0))
        host.fakeRagdoll.knockDownResult = true
        #expect(adapter.knockDown(Self.actor, from: .zero, magnitude: 2))
        host.fakeRagdoll.knockDownResult = false
        #expect(!adapter.knockDown(Self.actor, from: .zero, magnitude: 2))
    }

    @Test func aKnockMovesAnNPCThroughTheStreamer() {
        #expect(!adapter.knockActor(Self.actor, velocity: .zero, knockdown: false))
        host.fakeStreamer.actors.knockActorResult = true
        #expect(adapter.knockActor(Self.actor, velocity: SIMD3(1, 0, 0), knockdown: true))
        #expect(adapter.knockActor(.player, velocity: SIMD3(1, 0, 0), knockdown: false))
        #expect(host.fakeStreamer.actors.knockActorCalls.map(\.actor) == [Self.actor])
    }

    /// A crate that touched a placed shape and another body: the shape's reference takes
    /// the crate's mass, the crate takes none from the shape, and the body takes its mass.
    @Test func aBodysTouchesNameWhatItStruckAndTheMassBehindIt() throws {
        let crate = ReferenceKey.generated(1)
        let other = ReferenceKey.generated(2)
        let wall = ReferenceKey.plugin(name: "base.esm", objectID: 0x50)
        var bodies = DynamicBodyWorld()
        let volume = try #require(DynamicCollisionVolume.box(halfExtents: SIMD3(repeating: 10)))
        bodies.setCell(.interior(FormID(0x10)), placements: [DynamicBodyPlacement(
            key: crate, reference: FormID(0x200),
            definition: DynamicBodyDefinition(volumes: [volume], mass: 20),
            originPosition: .zero, orientation: .identityRotation
        )])
        bodies.bodies[0].touches = [
            DynamicBodyTouch(struck: .shape(FormID(0x50)), speed: 600),
            DynamicBodyTouch(struck: .body(other), speed: 300)
        ]
        host.fakeStreamer.dynamicBodiesValue = bodies
        var name = Data()
        name.appendUInt32(0x70)
        let fields = ESMFixture.field("NAME", name) + ESMFixture.field("DATA", Data(count: 24))
        let placed = try PlacedReference(record: ESMFixture.parseRecord(
            ESMFixture.record("REFR", formID: 0x50, data: fields)
        ))
        host.fakeStreamer.referenceEntryFormIDResult = RuntimeReferenceEntry(
            key: wall, formID: FormID(0x50), isPersistent: true, record: .reference(placed)
        )

        let touches = try #require(adapter.impulseBodies().first).touches
        #expect(touches == [
            ImpulseTouch(struck: wall, otherMass: 20, speed: 600),
            ImpulseTouch(struck: crate, otherMass: 0, speed: 600),
            ImpulseTouch(struck: other, otherMass: 20, speed: 300)
        ])
    }
}
