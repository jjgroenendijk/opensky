// The record a combat group keeps of one target. See
// docs/engine/detection.md#keeping-a-combat-target.

@testable import OpenSkyPerceptionInterface
import simd
import Testing

struct CombatTargetTrackTests {
    private let origin = SIMD3<Float>(0, 0, 0)

    private func seen(at position: SIMD3<Float>) -> CombatTargetSighting {
        CombatTargetSighting(value: 30, counts: true, position: position)
    }

    private func unseen(at position: SIMD3<Float>, value: Float = 0) -> CombatTargetSighting {
        CombatTargetSighting(value: value, counts: false, position: position)
    }

    /// A noticed track, `seconds` after the sighting, with the target at `position`.
    private func noticed(
        then position: SIMD3<Float>, for seconds: Int
    ) -> CombatTargetTrack {
        var track = CombatTargetTrack()
        track.advance(seen(at: origin), by: 1)
        for _ in 0 ..< seconds {
            track.advance(unseen(at: position), by: 1)
        }
        return track
    }

    @Test func theLastKnownPositionFollowsTheTargetForTenSeconds() {
        let near = SIMD3<Float>(700, 0, 0)
        #expect(noticed(then: near, for: 9).lastKnown == near)
        var track = noticed(then: near, for: 9)
        track.advance(unseen(at: SIMD3(760, 0, 0)), by: 1)
        #expect(track.lastKnown == near)
        #expect(track.phase == .noticed)
    }

    @Test func aTargetThatRunsFarIsNoLongerFollowed() {
        let track = noticed(then: SIMD3(800, 0, 0), for: 3)
        #expect(track.lastKnown == origin)
        #expect(track.phase == .noticed)
    }

    @Test func aStandingTargetIsLostAfterTwentySeconds() {
        #expect(noticed(then: origin, for: 18).phase == .noticed)
        #expect(noticed(then: origin, for: 19).phase == .lost)
        // A target that left the follow range is lost 10 s after it left.
        #expect(noticed(then: SIMD3(800, 0, 0), for: 10).phase == .lost)
    }

    @Test func aMemberThatLooksAtAnInvisibleTargetLosesIt() {
        var track = noticed(then: origin, for: 1)
        var sighting = unseen(at: origin, value: -5)
        sighting.memberSeesTarget = true
        track.advance(sighting, by: 1)
        #expect(track.phase == .noticed)
        sighting.isInvisible = true
        track.advance(sighting, by: 1)
        #expect(track.phase == .lost)
    }

    @Test func aMemberAtTheLastKnownPlaceLosesAHitTarget() {
        var track = CombatTargetTrack()
        var sighting = unseen(at: origin, value: -5)
        sighting.memberSeesLastKnown = true
        track.advance(sighting, by: 1)
        #expect(track.phase == .hidden)
        track.addSearchPlace(SIMD3(100, 0, 0))
        #expect(track.lastKnown == SIMD3(100, 0, 0))
        track.advance(sighting, by: 1)
        #expect(track.phase == .lost)
    }

    @Test func aPositiveValueThatDoesNotCountLosesTheTarget() {
        var track = CombatTargetTrack()
        track.advance(unseen(at: origin, value: 3), by: 1)
        #expect(track.phase == .lost)
        #expect(track.isListed)
        track.advance(seen(at: origin), by: 1)
        #expect(track.phase == .noticed)
    }

    @Test func aLostTargetIsDroppedAfterThirtySeconds() {
        var track = CombatTargetTrack()
        track.advance(unseen(at: origin, value: 3), by: 1)
        let dropped1 = track.advance(unseen(at: origin), by: 28)
        #expect(!dropped1)
        let dropped2 = track.advance(unseen(at: origin), by: 1)
        #expect(dropped2)
        #expect(track == CombatTargetTrack())
    }

    @Test func engagedMembersKeepALostTargetUntilNoneIsNearForSixtySeconds() {
        var track = CombatTargetTrack()
        track.advance(unseen(at: origin, value: 3), by: 1)
        var sighting = unseen(at: origin)
        sighting.hasEngagedMember = true
        sighting.nearestMember = 1000
        let dropped3 = track.advance(sighting, by: 100)
        #expect(!dropped3)
        sighting.nearestMember = 5000
        let dropped4 = track.advance(sighting, by: 59)
        #expect(!dropped4)
        let dropped5 = track.advance(sighting, by: 1)
        #expect(dropped5)
    }

    @Test func aNoticedTargetKeepsItsPlaceOverASearchPlace() {
        var track = noticed(then: origin, for: 1)
        track.addSearchPlace(SIMD3(500, 0, 0))
        #expect(track.lastKnown == origin)
        var none = CombatTargetTrack()
        none.advance(unseen(at: origin), by: .nan)
        #expect(none == CombatTargetTrack())
    }
}
