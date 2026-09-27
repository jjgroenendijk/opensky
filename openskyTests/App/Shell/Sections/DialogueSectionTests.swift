// World > Dialogue & Voice > Dialogue section coverage (issue #205; the
// section moved to the milestone's own destination with issue #209). Uses only
// synthetic provider state; the real-install bring-up gate lives in the
// env-gated acceptance test and in `openskycli swf dialogue-menu`.
//
// Two things are pinned here and nowhere else: the accessibility ids, which are
// the UI-test API and must never change silently, and the readout wording,
// which is how the milestone's acceptance question — "did Escape leave the
// world exactly as it was" — is answered from a readout rather than by eye.

import AppKit
@testable import opensky
import Testing

@MainActor
struct DialogueSectionTests {
    private func makePanel(
        _ provider: FakeWorldProviders
    ) -> DialoguePanelViewController {
        let panel = DialoguePanelViewController()
        panel.dialogueProvider = provider
        panel.loadViewIfNeeded()
        return panel
    }

    private func row(_ id: UInt32, _ text: String, goodbye: Bool = false)
        -> DialogueTopicRow
    {
        DialogueTopicRow(
            topic: FormID(id),
            info: FormID(id + 0x100),
            text: text,
            endsConversation: goodbye
        )
    }

    @Test
    func controlsExposeStableIdentifiers() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        let section = panel.dialogueSection
        let controls: [(NSControl, String)] = [
            (section.openControl, "DialogueOpenControl"),
            (section.leaveControl, "DialogueLeaveControl"),
            (section.upControl, "DialogueUpControl"),
            (section.downControl, "DialogueDownControl"),
            (section.chooseControl, "DialogueChooseControl")
        ]
        for (control, identifier) in controls {
            #expect(control.accessibilityIdentifier() == identifier)
        }
        #expect(section.sectionIdentifier == "dialogue")
    }

    @Test
    func everyControlReachesTheSameEntryPointsTheKeysDo() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        let section = panel.dialogueSection
        section.openControl.performClick(nil)
        section.upControl.performClick(nil)
        section.downControl.performClick(nil)
        section.chooseControl.performClick(nil)
        section.leaveControl.performClick(nil)
        #expect(provider.dialogue.openCount == 1)
        #expect(provider.dialogue.closeCount == 1)
        // The panel buttons and the live keys cannot diverge because they are
        // the same `MenuInputEvent` path.
        #expect(provider.dialogue.events == [.move(.up), .move(.down), .button(.accept)])
    }

    @Test
    func readoutNamesTheTalkTargetWhenTheCrosshairIsOnOne() {
        let provider = FakeWorldProviders()
        provider.dialogue.snapshot = makeDialogueSnapshot(
            topicCount: 15037,
            infoCount: 31465,
            targetName: "Belethor"
        )
        let panel = makePanel(provider)
        panel.dialogueSection.refreshReadout()
        let text = panel.dialogueSection.topicsReadout
        #expect(text.contains("15037 topics"))
        #expect(text.contains("Talk target: Belethor"))
        #expect(text.contains("Conversation: closed"))
    }

    @Test
    func readoutStatesThatAnOpenConversationLeavesTheWorldRunning() {
        let provider = FakeWorldProviders()
        provider.dialogue.snapshot = makeDialogueSnapshot(
            speaker: "Belethor",
            isOpen: true,
            openMenus: ["Dialogue Menu"],
            worldSimPaused: false,
            state: "topicList",
            rows: [row(1, "Ask about the shop"), row(2, "Never mind", goodbye: true)],
            selectedIndex: 1
        )
        let panel = makePanel(provider)
        panel.dialogueSection.refreshReadout()
        let text = panel.dialogueSection.topicsReadout
        #expect(text.contains("Conversation: Belethor · topicList"))
        // The whole milestone in one readout line.
        #expect(text.contains("Menu stack: Dialogue Menu · world running"))
        #expect(text.contains("> 1: \"Never mind\" info 00000102 (goodbye)"))
    }

    @Test
    func readoutSaysWhyATopicIsNotListed() {
        let provider = FakeWorldProviders()
        provider.dialogue.snapshot = makeDialogueSnapshot(
            isOpen: true,
            rejections: [
                DialogueRejectionRow(
                    topic: FormID(0x1360E),
                    reasons: ["conditions failed", "not reached"]
                )
            ],
            unresolvedConditionCount: 3
        )
        let panel = makePanel(provider)
        panel.dialogueSection.refreshReadout()
        let text = panel.dialogueSection.conditionsReadout
        #expect(text.contains("Unresolved condition calls: 3"))
        #expect(text.contains("0001360E: conditions failed, not reached"))
    }

    @Test
    func aSessionWithNoPluginSaysSoRatherThanShowingZeros() {
        let provider = FakeWorldProviders()
        provider.dialogue.snapshot = .empty
        let panel = makePanel(provider)
        panel.dialogueSection.refreshReadout()
        #expect(panel.dialogueSection.topicsReadout.contains("no plugin loaded"))
        #expect(panel.dialogueSection.conditionsReadout.contains("no plugin loaded"))
    }

    @Test
    func anOpenConversationIsTheSectionsOverriddenStateAndTheResetLeavesIt() {
        let provider = FakeWorldProviders()
        provider.dialogue.snapshot = makeDialogueSnapshot(isOpen: true)
        let panel = makePanel(provider)
        #expect(panel.dialogueSection.isOverridden)
        panel.dialogueSection.performResetToDefaults()
        #expect(provider.dialogue.closeCount == 1)
    }

    @Test
    func theSectionSitsUnderHUDAndInteraction() {
        let panel = makePanel(FakeWorldProviders())
        #expect(panel.makeSections().contains { $0 === panel.dialogueSection })
    }
}
