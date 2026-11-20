// The social state a save keeps: timers as they were, times counted back from the
// clock, a conversation on its speaker, and no recent-partner list.

import OpenSkyFormatsESM
import OpenSkyQuestsInterface
import Testing

struct SavedSocialStateTests {
    private let speaker = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BBD)
    private let partner = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BBE)
    private let body = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BBF)

    private func running(at start: Double) -> SocialState {
        var state = SocialState()
        state.socialTimers[speaker] = 12
        state.recentTimers[partner] = 30
        state.recentPartners[speaker] = [partner]
        state.bodyChecks[body] = start - 5
        state.conversations = [SocialConversation(
            speaker: speaker, partner: partner, startedAt: start - 1.5,
            phase: .approaching, goal: SIMD3(1, 2, 3)
        )]
        return state
    }

    @Test func aLoadKeepsTheTimersAndTheConversationAgainstItsOwnClock() throws {
        let saved = running(at: 100).saved(now: 100)
        #expect(saved[speaker]?.socialTimer == 12)
        #expect(saved[partner]?.recentTimer == 30)
        #expect(saved[body]?.bodyCheckAge == 5)
        #expect(saved[partner]?.conversation == nil)
        let restored = SocialState(saved: saved, now: 7)
        #expect(restored.socialTimers == [speaker: 12])
        #expect(restored.recentTimers == [partner: 30])
        #expect(restored.bodyChecks == [body: 2])
        let talk = try #require(restored.conversation(of: partner))
        #expect(talk.speaker == speaker)
        #expect(talk.startedAt == 5.5)
        #expect(talk.phase == .approaching)
        #expect(talk.goal == SIMD3(1, 2, 3))
        #expect(restored.recentPartners.isEmpty)
        #expect(restored.lastPass == nil)
    }

    @Test func anEmptyStateKeepsNothing() {
        #expect(SocialState().saved(now: 50).isEmpty)
    }
}
