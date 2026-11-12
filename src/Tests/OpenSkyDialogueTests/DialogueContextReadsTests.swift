// Whether a speaker counts as the voice a topic forces.

@testable import OpenSkyConditions
@testable import OpenSkyDialogue
import OpenSkyFormatsESM
import OpenSkyWorldState
import Testing

@MainActor
struct DialogueContextReadsTests {
    @Test func aSpeakerTheContextDoesNotKnowIsTakenAsTheForcedVoice() {
        #expect(DialogueContextReads.speaks(
            .generated(4), as: FormID(0x10), in: ConditionContext()
        ))
    }
}
