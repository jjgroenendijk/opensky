// Footstep annotations that no footstep tag matches, so they play nothing.

import Foundation
@testable import OpenSkyAudio
import Testing

struct FootstepUnansweredTagTests {
    @Test func misspelledAndPaddedTagsAreUnanswered() {
        let known: Set = ["footleft", "footback"]
        #expect(FootstepStore.isUnanswered(tag: "FootFornt", known: known))
        #expect(FootstepStore.isUnanswered(tag: "FootBack\r", known: known))
        #expect(FootstepStore.isUnanswered(tag: "FootRight\n", known: known))
    }

    @Test func realTagsAndOtherEventsAreNot() {
        let known: Set = ["footleft"]
        #expect(!FootstepStore.isUnanswered(tag: "FootLeft", known: known))
        #expect(!FootstepStore.isUnanswered(tag: "HitFrame\r", known: known))
        #expect(!FootstepStore.isUnanswered(tag: "SoundPlay.TestStep", known: known))
    }
}
