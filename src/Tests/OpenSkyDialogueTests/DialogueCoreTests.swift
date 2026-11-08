// The speaker focus state machine and the readout sentences, with plain values.

@testable import OpenSkyDialogue
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
import Testing

@MainActor
struct DialogueCoreTests {
    private let first = DialogueRuntimeFixture.infoKey(0x10)
    private let second = DialogueRuntimeFixture.infoKey(0x11)

    @Test func aNewSpeakerIsHeldThenFaced() {
        let step = DialogueCore.focus(held: nil, speaker: first)
        #expect(step.held == first)
        #expect(step.effects == [.hold(first), .face(first)])
    }

    /// The hold runs once per speaker, the turn every frame.
    @Test func theHeldSpeakerIsOnlyFacedAgain() {
        let step = DialogueCore.focus(held: first, speaker: first)
        #expect(step.held == first)
        #expect(step.effects == [.face(first)])
    }

    @Test func aDifferentSpeakerReleasesTheHeldOneFirst() {
        let step = DialogueCore.focus(held: first, speaker: second)
        #expect(step.held == second)
        #expect(step.effects == [.release(first), .hold(second), .face(second)])
    }

    @Test func noSpeakerReleasesTheHeldOne() {
        let step = DialogueCore.focus(held: first, speaker: nil)
        #expect(step.held == nil)
        #expect(step.effects == [.release(first)])
    }

    @Test func nobodyHeldAndNobodyWantedDoesNothing() {
        let step = DialogueCore.focus(held: nil, speaker: nil)
        #expect(step.held == nil)
        #expect(step.effects.isEmpty)
    }

    @Test func openedTextCountsTopicsAndRejections() {
        #expect(DialogueCore.openedText(speaker: "Lydia", topicCount: 2, rejectedCount: 1)
            == "opened with Lydia: 2 topics, 1 rejected")
    }
}
