// MagicHoldCore: hold renewal and ageing, the light offset, the Telekinesis steer, and
// the Guide trail.

@testable import OpenSkyFormatsESM
@testable import OpenSkyMagic
import simd
import Testing

struct MagicHoldCoreTests {
    private static let effect = ReferenceKey.plugin(name: "base.esm", objectID: 0x70)

    private static func hold(_ kind: MagicHold.Kind, remaining: Float) -> MagicHold {
        MagicHold(kind: kind, caster: .player, effect: effect, remaining: remaining)
    }

    /// A concentration landing lasts until the next one, a second later.
    @Test func aLandingWithNoDurationLastsPastTheNextLanding() {
        #expect(MagicHoldCore.lifetime(duration: 0) == MagicHoldCore.renewalSeconds)
        #expect(MagicHoldCore.lifetime(duration: 30) == 30)
    }

    @Test func renewingExtendsTheHoldOfTheSameKindAndCaster() {
        let holds = [Self.hold(.telekinesis, remaining: 0.2)]
        let renewed = MagicHoldCore.renewing(Self.hold(.telekinesis, remaining: 1.5), in: holds)
        #expect(renewed.map(\.remaining) == [1.5])

        let added = MagicHoldCore.renewing(Self.hold(.guide, remaining: 1.5), in: holds)
        #expect(added.map(\.kind) == [.telekinesis, .guide])
    }

    @Test func advancingSplitsRunningFromEnded() {
        let holds = [Self.hold(.detectLife, remaining: 0.5), Self.hold(.grabActor, remaining: 2)]
        let (running, ended) = MagicHoldCore.advancing(holds, by: 1)
        #expect(running.map(\.kind) == [.grabActor])
        #expect(ended.map(\.kind) == [.detectLife])
    }

    /// Looking north along +Y with the vanilla offsets: 13 ahead, 28 to the left, 60 down.
    @Test func aSelfLightFloatsAtTheGameSettingOffsets() {
        let position = MagicHoldCore.lightPosition(
            eye: SIMD3(0, 0, 100), forward: simd_normalize(SIMD3(0, 1, -1)), settings: .vanilla
        )
        #expect(simd_distance(position, SIMD3(-28, 13, 40)) < 0.001)
    }

    /// A body already at its hold point and at rest only needs its weight carried.
    @Test func aBodyAtItsHoldPointIsOnlyLifted() {
        let body = MagicHeldBody(position: .zero, velocity: .zero, mass: 2)
        let impulse = MagicHoldCore.steeringImpulse(
            body, toward: .zero, delta: 0.5, gravity: 10
        )
        #expect(impulse == SIMD3(0, 0, 10))
    }

    @Test func aTrailStopsAtItsWaypointLimit() {
        let path: [SIMD3<Float>] = [.zero, SIMD3(100, 0, 0), SIMD3(100, 100, 0)]
        let trail = MagicHoldCore.trail(along: path, spacing: 40, limit: 4)
        let expected: [SIMD3<Float>] = [
            SIMD3(40, 0, 0), SIMD3(80, 0, 0), SIMD3(100, 20, 0), SIMD3(100, 60, 0)
        ]
        #expect(trail.count == expected.count)
        #expect(zip(trail, expected).allSatisfy { simd_distance($0, $1) < 0.001 })
        #expect(MagicHoldCore.trail(along: path, spacing: 40, limit: 0).isEmpty)
    }

    @Test func telekinesisReachIsTheBaseTimesTheMult() {
        var settings = MagicHoldSettings.vanilla
        settings.telekinesisDistanceMult = 1.5
        #expect(settings.telekinesisReach == 3150)
    }
}
