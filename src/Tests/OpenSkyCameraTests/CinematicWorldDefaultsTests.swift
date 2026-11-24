// A cinematic world that tracks no shots has no projectile to follow, and counts every
// target as dead, so a ranged kill cam ends on its own limits.

@testable import OpenSkyCamera
import OpenSkyFormatsESM
import Testing

@MainActor
struct CinematicWorldDefaultsTests {
    @Test func aWorldWithoutShotsFollowsNoneAndCountsTargetsDead() {
        let world = FakeCinematicWorld()
        #expect(world.cinematicProjectileAnchor(1) == nil)
        #expect(world.cinematicTargetIsDead(.player))
    }
}
