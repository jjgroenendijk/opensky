// The object melee magnetism turns with: an actor under the view ray, else the
// crosshair's activation target.

import OpenSkyActorAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkySessionTesting
import OpenSkyWorldInterface
import simd
import Testing

@MainActor
struct MagnetismSightingTests {
    private static let enemy = ReferenceKey.generated(31)

    private func ray() throws -> InteractionRay {
        try #require(InteractionRay(
            origin: SIMD3(0, 0, 64), direction: SIMD3(1, 0, 0), maximumDistance: 750
        ))
    }

    private func input(isDead: Bool = false) -> MagnetismSightingInput {
        var input = MagnetismSightingInput()
        input.actors = [
            CombatActorObservation(key: .player, feet: SIMD3(100, 0, 0)),
            CombatActorObservation(key: Self.enemy, feet: SIMD3(500, 0, 0), isDead: isDead)
        ]
        return input
    }

    private static let lever = InteractionTarget(
        interaction: PlacedInteraction(
            reference: FormID(0x40), base: FormID(0x41), position: SIMD3(120, 0, 60),
            name: "Lever", action: .activate, actionLabel: "Activate", sounds: nil
        ),
        hitPosition: SIMD3(118, 0, 64), distance: 118
    )

    @Test func aLivingActorUnderTheRayIsTheTarget() throws {
        let sighting = try ActorWorldAdapter.magnetismSighting(along: ray(), input())
        #expect(sighting == MeleeMagnetism.Sighting(actor: Self.enemy, position: SIMD3(500, 0, 0)))
    }

    @Test func aDeadActorTheOwnMountAndAnActorBehindAWallGiveNoTarget() throws {
        var dead = input(isDead: true)
        dead.crosshair = Self.lever
        #expect(try ActorWorldAdapter.magnetismSighting(along: ray(), dead) == nil)
        var mount = input()
        mount.ownMount = Self.enemy
        #expect(try ActorWorldAdapter.magnetismSighting(along: ray(), mount) == nil)
        var walled = input()
        walled.wallDistance = { _ in 300 }
        #expect(try ActorWorldAdapter.magnetismSighting(along: ray(), walled) == nil)
    }

    @Test func withNoActorTheCrosshairsObjectIsTheTarget() throws {
        var none = MagnetismSightingInput()
        #expect(try ActorWorldAdapter.magnetismSighting(along: ray(), none) == nil)
        none.crosshair = Self.lever
        let sighting = try ActorWorldAdapter.magnetismSighting(along: ray(), none)
        #expect(sighting == MeleeMagnetism.Sighting(actor: nil, position: SIMD3(118, 0, 64)))
    }

    @Test func theAdapterReadsTheCrosshairOfTheSession() throws {
        let host = ActorHost()
        let actors = ActorWorldAdapter(game: host, stage: nil)
        #expect(try actors.magnetismSighting(along: ray()) == nil)
        host.fakeStreamer.interactionTarget = Self.lever
        let sighting = try actors.magnetismSighting(along: ray())
        #expect(sighting == MeleeMagnetism.Sighting(actor: nil, position: SIMD3(118, 0, 64)))
    }
}
