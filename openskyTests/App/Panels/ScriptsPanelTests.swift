// World > Scripts verification-surface coverage (issue #278): the panel the
// registry factory builds, the literal accessibility-id contract, the readouts
// each section renders from one snapshot, and the provider round-trip for every
// control — which tick count each step button carries, and how the pause
// checkbox and the destination's override state stay in step.

import AppKit
@testable import opensky
import Testing

struct ScriptsPanelTests {
    @Test @MainActor
    func registryFactoryBuildsThePanelWithProvidersWired() throws {
        let descriptor = try #require(DestinationRegistry.destination(id: "scripts"))
        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("scripts is not a world inspector")
            return
        }
        let providers = FakeWorldProviders()
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers)) as? ScriptsPanelViewController
        )
        panel.loadViewIfNeeded()
        #expect(descriptor.title == "Scripts")
        #expect(descriptor.section == .world)
        #expect(descriptor.sidebarIdentifier == "Destination-scripts")
        #expect(panel.provider === providers)
    }

    /// Accessibility ids are the UI-test API (docs/tools/app-ui.md); pin the
    /// Scripts set literally.
    @Test @MainActor
    func accessibilityIdentifiersArePinned() {
        let panel = ScriptsPanelViewController()
        panel.loadViewIfNeeded()
        #expect(panel.instancesSection.sectionIdentifier == "scriptInstances")
        #expect(panel.questsSection.sectionIdentifier == "scriptQuests")
        #expect(panel.eventsSection.sectionIdentifier == "scriptEvents")
        #expect(panel.schedulerSection.sectionIdentifier == "scriptScheduler")
        #expect(panel.nativeTallySection.sectionIdentifier == "scriptNativeTally")

        #expect(panel.scriptPauseControl.accessibilityIdentifier() == "ScriptPauseControl")
        #expect(panel.scriptStepControl.accessibilityIdentifier() == "ScriptStepControl")
        #expect(panel.scriptBurstControl.accessibilityIdentifier() == "ScriptBurstControl")
        #expect(
            panel.questsSection.questAliasControl.accessibilityIdentifier()
                == "ScriptQuestAliasControl"
        )

        for identifier in [
            "ScriptInstancesStatsLabel", "ScriptQuestsStatsLabel", "ScriptEventsStatsLabel",
            "ScriptSchedulerStatsLabel", "ScriptNativeTallyStatsLabel",
            "ScriptQuestAliasStatsLabel"
        ] {
            #expect(scriptsReadout(identifier, in: panel.view) != nil, "\(identifier) is missing")
        }
    }

    @Test @MainActor
    func controlsHaveVisibleFramesInsideDocument() throws {
        let panel = ScriptsPanelViewController()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        panel.view.layoutSubtreeIfNeeded()

        for control: NSView in [
            panel.scriptPauseControl, panel.scriptStepControl, panel.scriptBurstControl
        ] {
            #expect(!control.isHidden)
            #expect(control.frame.height > 0)
            let documentFrame = control.convert(control.bounds, to: scrollView.documentView)
            #expect(scrollView.documentView?.bounds.intersects(documentFrame) == true)
        }
    }

    /// The step buttons are the milestone's manual transport, so the exact tick
    /// count each one carries is part of the contract.
    @Test @MainActor
    func stepAndBurstCarryTheirTickCounts() {
        let panel = ScriptsPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeScriptProvider()
        panel.provider = fake

        sendScriptsControl(panel.scriptStepControl)
        sendScriptsControl(panel.scriptBurstControl)

        #expect(fake.stepCalls == [1, 20])
        #expect(ScriptSchedulerSection.burstTicks == 20)
        #expect(panel.scriptBurstControl.title == "Step x20")
        // Stepping is momentary: it must not leave the destination overridden.
        #expect(!panel.isOverridden)
    }

    /// The checkbox writes the VM pause and nothing else — never the engine's
    /// world-simulation pause, which is a different freeze under System Menu.
    @Test @MainActor
    func pauseCheckboxTogglesTheVMPause() {
        let panel = ScriptsPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeScriptProvider()
        panel.provider = fake

        panel.scriptPauseControl.state = .on
        sendScriptsControl(panel.scriptPauseControl)
        #expect(fake.setPausedCalls == [true])
        #expect(panel.schedulerSection.isOverridden)
        #expect(panel.isOverridden)
        #expect(panel.schedulerSection.readout.contains("VM: paused"))

        panel.scriptPauseControl.state = .off
        sendScriptsControl(panel.scriptPauseControl)
        #expect(fake.setPausedCalls == [true, false])
        #expect(!panel.isOverridden)
        #expect(panel.schedulerSection.readout.contains("VM: running"))
    }

    /// A snapshot that arrives already paused has to reach the checkbox, so the
    /// control never disagrees with the engine it claims to show.
    @Test @MainActor
    func pauseCheckboxReflectsTheSnapshot() {
        let panel = ScriptsPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeScriptProvider()
        fake.scriptsSnapshot = makeScriptsSnapshot(isPaused: true)
        panel.provider = fake
        panel.startInspecting()
        defer { panel.stopInspecting() }

        #expect(panel.scriptPauseControl.state == .on)
        #expect(panel.schedulerSection.isOverridden)
    }

    /// The destination-level reset resumes the VM and clears the sidebar dot,
    /// running through the same section hook the registry calls.
    @Test @MainActor
    func resetToDefaultsResumesTheVM() {
        let panel = ScriptsPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeScriptProvider()
        fake.scriptsSnapshot = makeScriptsSnapshot(isPaused: true)
        panel.provider = fake
        #expect(panel.isOverridden)

        panel.schedulerSection.performResetToDefaults()
        #expect(fake.setPausedCalls == [false])
        #expect(!panel.isOverridden)
        #expect(panel.scriptPauseControl.state == .off)
    }

    @Test @MainActor
    func readoutsRenderSnapshotValuesAcrossEverySection() {
        let panel = ScriptsPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeScriptProvider()
        fake.scriptsSnapshot = makeScriptsSnapshot(
            instanceCount: 12,
            targetDescription: "skyrim.esm:00003F",
            targetScripts: ["defaultAlias", "WIChangeLocation04"],
            recentEvents: ["OnActivate skyrim.esm:00003F"],
            droppedRecentEventCount: 7,
            pendingEventCount: 3,
            pendingWaitCount: 2,
            pendingTimerCount: 5,
            tickCount: 120,
            budgetEvents: 100,
            budgetInstructions: 20000,
            lastTickSteps: 4,
            nativeCallTotal: 4210,
            implementedNativeNameCount: 37,
            unimplementedNativeTotal: 12,
            topUnimplementedNatives: [ScriptsNativeCount(name: "Game.GetPlayer", count: 8)]
        )
        panel.provider = fake
        panel.startInspecting()
        defer { panel.stopInspecting() }

        #expect(panel.instancesSection.readout.contains("Instances: 12"))
        #expect(panel.instancesSection.readout.contains("Target: skyrim.esm:00003F"))
        #expect(panel.instancesSection.readout.contains("defaultAlias, WIChangeLocation04"))
        #expect(panel.eventsSection.readout.contains("Pending events: 3"))
        #expect(panel.eventsSection.readout.contains("Dropped: 7"))
        #expect(panel.eventsSection.readout.contains("OnActivate skyrim.esm:00003F"))
        #expect(panel.schedulerSection.readout.contains("Pending waits: 2"))
        #expect(panel.schedulerSection.readout.contains("Ticks: 120"))
        #expect(panel.nativeTallySection.readout.contains("Native calls: 4210"))
        #expect(panel.nativeTallySection.readout.contains("1. Game.GetPlayer 8"))
    }

    /// The alias inspector is the sidebar path for issue #183: picking a quest
    /// shows every alias it declares, what should fill it, and what did.
    @Test @MainActor
    func questAliasInspectorShowsFilledAndEmptyAliases() {
        let panel = ScriptsPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeScriptProvider()
        fake.scriptsSnapshot = makeScriptsSnapshot(
            runningQuestCount: 2,
            questAliasInstanceCount: 1,
            filledAliasCount: 3,
            aliasQuestCount: 2,
            lastQuestAliasFill: "MGRArniel01[1] -> skyrim.esm:0123AB"
        )
        fake.questAliasTables = ["MGRArniel01": ScriptQuestAliasInspection(
            editorID: "MGRArniel01",
            formIDText: "skyrim.esm:06A086",
            isRunning: true,
            rows: [
                ScriptQuestAliasRow(
                    aliasID: 0,
                    name: "Arniel",
                    fillType: "specific reference",
                    isOptional: false,
                    reference: "skyrim.esm:0123AB"
                ),
                ScriptQuestAliasRow(
                    aliasID: 1,
                    name: "Book",
                    fillType: "find matching reference",
                    isOptional: true,
                    reference: nil
                )
            ]
        )]
        panel.provider = fake
        panel.questsSection.questAliasControl.stringValue = "MGRArniel01"
        panel.startInspecting()
        defer { panel.stopInspecting() }

        #expect(panel.questsSection.readout.contains("Aliases filled: 3 across 2 quests"))
        #expect(panel.questsSection.readout.contains("Alias instances: 1"))
        #expect(
            panel.questsSection.readout.contains("Last fill: MGRArniel01[1] -> skyrim.esm:0123AB")
        )
        let aliases = panel.questsSection.aliasReadout
        #expect(aliases.contains("MGRArniel01 (skyrim.esm:06A086)  running  filled 1/2"))
        #expect(aliases.contains("[0] Arniel (specific reference) -> skyrim.esm:0123AB"))
        #expect(aliases.contains("[1] Book (find matching reference, optional) -> empty"))
        #expect(panel.questsSection.aliasEditorID == "MGRArniel01")
    }

    /// A name nothing defines says so rather than reading as "no selection".
    @Test @MainActor
    func questAliasInspectorNamesAnUnknownQuest() {
        let panel = ScriptsPanelViewController()
        panel.loadViewIfNeeded()
        // Held in a local: the panel's provider reference is weak, so a
        // temporary would be gone before the first refresh.
        let fake = FakeScriptProvider()
        panel.provider = fake
        panel.questsSection.questAliasControl.stringValue = "NoSuchQuest"
        panel.startInspecting()
        defer { panel.stopInspecting() }

        #expect(panel.questsSection.aliasReadout == "No loaded plugin defines NoSuchQuest.")
    }

    /// A session with no VM states that, rather than showing zeros that would
    /// read as a running but idle VM.
    @Test @MainActor
    func missingProviderReadsAsUnavailable() {
        let panel = ScriptsPanelViewController()
        panel.loadViewIfNeeded()
        panel.startInspecting()
        defer { panel.stopInspecting() }

        #expect(panel.instancesSection.readout == "Papyrus: unavailable")
        #expect(panel.eventsSection.readout == "Papyrus: unavailable")
        #expect(panel.schedulerSection.readout == "Papyrus: unavailable")
        #expect(panel.nativeTallySection.readout == "Papyrus: unavailable")
        #expect(!panel.isOverridden)
    }
}
