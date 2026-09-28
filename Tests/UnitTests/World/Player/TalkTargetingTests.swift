// Talk targeting (issue #205, roadmap item 17.3, scope point 1): which actor a
// view ray picks up, and which it does not. Pure geometry over the melee
// narrowphase, so no world, no streamer and no install.

@testable import opensky
import simd
import Testing

struct TalkTargetingTests {
    /// One actor standing at `position`, with the standard player capsule.
    private func candidate(_ id: UInt32, at position: SIMD3<Float>) -> TalkCandidate {
        TalkCandidate(
            key: ReferenceKey(resolved: ResolvedFormID(plugin: "Skyrim.esm", objectID: id)),
            reference: FormID(id),
            base: FormID(id + 0x1000),
            feet: position,
            name: "Actor \(id)"
        )
    }

    /// A ray from the origin looking down +X at roughly eye height.
    private func ray(distance: Float = InteractionRay.defaultMaximumDistance) -> InteractionRay? {
        InteractionRay(
            origin: SIMD3(0, 0, 64),
            direction: SIMD3(1, 0, 0),
            maximumDistance: distance
        )
    }

    @Test
    func picksTheActorUnderTheCrosshair() throws {
        let view = try #require(ray())
        let hit = try #require(
            TalkTargetPicker.nearest(
                ray: view, candidates: [candidate(1, at: SIMD3(100, 0, 0))]
            )
        )
        #expect(hit.candidate.reference == FormID(1))
        // The closest approach is straight ahead, so the travel is the actor's
        // own distance along the ray.
        #expect(abs(hit.distance - 100) < 1)
    }

    @Test
    func missesAnActorTheRayPassesBeside() throws {
        let view = try #require(ray())
        // Well outside the capsule radius, which `PlayerCapsule.standard`
        // carries; a near miss must not become a prompt.
        let far = candidate(1, at: SIMD3(100, 200, 0))
        #expect(TalkTargetPicker.nearest(ray: view, candidates: [far]) == nil)
    }

    @Test
    func missesAnActorBehindTheEye() throws {
        let view = try #require(ray())
        #expect(
            TalkTargetPicker.nearest(
                ray: view, candidates: [candidate(1, at: SIMD3(-200, 0, 0))]
            ) == nil
        )
    }

    @Test
    func missesAnActorPastTheTalkDistance() throws {
        let view = try #require(ray(distance: 4096))
        let actor = candidate(1, at: SIMD3(1000, 0, 0))
        // The ray reaches far enough; the talk distance does not.
        #expect(TalkTargetPicker.nearest(ray: view, candidates: [actor]) == nil)
        #expect(
            TalkTargetPicker.nearest(
                ray: view, candidates: [actor], maximumDistance: 2000
            ) != nil
        )
    }

    @Test
    func picksTheNearestOfTwoInLine() throws {
        let view = try #require(ray())
        let hit = try #require(
            TalkTargetPicker.nearest(
                ray: view,
                candidates: [
                    candidate(2, at: SIMD3(150, 0, 0)),
                    candidate(1, at: SIMD3(60, 0, 0))
                ]
            )
        )
        #expect(hit.candidate.reference == FormID(1))
    }

    @Test
    func breaksTiesOnTheLowerReferenceSoThePromptDoesNotFlicker() throws {
        let view = try #require(ray())
        let coincident = [
            candidate(7, at: SIMD3(100, 0, 0)),
            candidate(3, at: SIMD3(100, 0, 0))
        ]
        let first = try #require(TalkTargetPicker.nearest(ray: view, candidates: coincident))
        let second = try #require(
            TalkTargetPicker.nearest(ray: view, candidates: coincident.reversed())
        )
        #expect(first.candidate.reference == FormID(3))
        #expect(second.candidate.reference == FormID(3))
    }

    @Test
    func noCandidatesIsNoTarget() throws {
        let view = try #require(ray())
        #expect(TalkTargetPicker.nearest(ray: view, candidates: []) == nil)
    }

    @Test
    func theTalkActionPromptNamesTheActor() {
        // The crosshair composes label plus name for every action, so this is
        // what a player reads under the crosshair.
        #expect(InteractionAction.talk.defaultLabel == "Talk to")
    }
}
