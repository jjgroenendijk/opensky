// World > Quests & Journal > Scenes and Story Manager, and World > Dialogue &
// Voice > Dialogue Branches, with the provider fake: pinned ids, visible
// controls, and each control driving the fake.

import AppKit
@testable import OpenSky
@testable import OpenSkyDialogue
@testable import OpenSkyQuests
import Testing

@MainActor
struct StoryPanelTests {
    private func tap(_ control: NSControl) {
        control.sendAction(control.action, to: control.target)
    }

    private func journal(_ provider: FakeWorldProviders) -> JournalPanelViewController {
        let panel = JournalPanelViewController()
        panel.loadViewIfNeeded()
        panel.sceneProvider = provider
        panel.storyProvider = provider
        return panel
    }

    private func dialogue(_ provider: FakeWorldProviders) -> DialoguePanelViewController {
        let panel = DialoguePanelViewController()
        panel.loadViewIfNeeded()
        panel.branchProvider = provider
        return panel
    }

    @Test func accessibilityIdentifiersArePinned() {
        let provider = FakeWorldProviders()
        let panel = journal(provider)
        let branches = dialogue(provider).branchesSection
        #expect(panel.scenesSection.sectionIdentifier == "scenes")
        #expect(panel.storySection.sectionIdentifier == "storyManager")
        #expect(branches.sectionIdentifier == "dialogueBranches")
        let controls: [(NSView, String)] = [
            (panel.scenesSection.sceneControl, "ScenesSceneControl"),
            (panel.scenesSection.startControl, "ScenesStartControl"),
            (panel.scenesSection.stopControl, "ScenesStopControl"),
            (panel.storySection.eventControl, "StoryEventControl"),
            (panel.storySection.keywordControl, "StoryKeywordControl"),
            (panel.storySection.valueControl, "StoryValueControl"),
            (panel.storySection.fireControl, "StoryFireControl"),
            (branches.filterControl, "DialogueBranchFilterControl")
        ]
        for (control, identifier) in controls {
            #expect(control.accessibilityIdentifier() == identifier)
        }
    }

    @Test func storyControlsHaveVisibleFrames() throws {
        let panel = journal(FakeWorldProviders())
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 1600)
        panel.view.layoutSubtreeIfNeeded()
        let controls: [NSControl] = [
            panel.scenesSection.sceneControl, panel.scenesSection.startControl,
            panel.storySection.eventControl, panel.storySection.fireControl
        ]
        for control in controls {
            let name = control.accessibilityIdentifier()
            #expect(!control.isHidden, "\(name) hidden")
            #expect(control.frame.height > 0, "\(name) frame=\(control.frame)")
            let documentFrame = control.convert(control.bounds, to: scrollView.documentView)
            #expect(scrollView.documentView?.bounds.intersects(documentFrame) == true)
        }
    }

    @Test func sceneControlsListStartAndStop() {
        let provider = FakeWorldProviders()
        let section = journal(provider).scenesSection
        section.refreshReadout()
        #expect(section.listReadout == "TestScene: 3 phases, 2 actions, 1 actors")
        section.sceneControl.stringValue = "TestScene"
        tap(section.startControl)
        #expect(provider.story.scenePlaying)
        #expect(section.readout.contains("Playing: TestScene, phase 1 of 3, running 0"))
        tap(section.stopControl)
        #expect(!provider.story.scenePlaying)
        #expect(section.readout.contains("Last action: stopped"))
    }

    @Test func storyControlsShowTheTreeAndFire() {
        let provider = FakeWorldProviders()
        let section = journal(provider).storySection
        section.syncControls()
        section.refreshReadout()
        #expect(section.eventControl.itemTitles == ["KILL"])
        #expect(section.listReadout == "Tree:\nKillEvents\n  KillQuests: TestQuest")
        tap(section.fireControl)
        #expect(provider.story.fired == ["KILL"])
        #expect(section.readout.contains("Event nodes: 1, fired 1"))
        #expect(section.readout.contains("Session start: 1 of 1 started"))
    }

    @Test func branchReadoutShowsScoping() {
        // The panel holds its provider weakly, so the test keeps it alive.
        let provider = FakeWorldProviders()
        let section = dialogue(provider).branchesSection
        section.refreshReadout()
        #expect(section.readout.contains("Branches: 2, blocking 1"))
        #expect(section.readout.contains("Not a branch start: 3"))
        #expect(section.listReadout == "TestBranch: top-level; starts TestTopic; 2 topics")
        withExtendedLifetime(provider) {}
    }
}
