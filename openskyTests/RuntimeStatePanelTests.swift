// World > Runtime State verification-surface coverage (M10.1.5): the panel the
// registry factory builds, the literal accessibility-id contract, and the
// provider round-trips for every button — which target selector each mutation
// carries, which slot save and load pass, and how a failed save reads.

import AppKit
@testable import opensky
import Testing

struct RuntimeStatePanelTests {
    @Test @MainActor
    func registryFactoryBuildsThePanelWithProvidersWired() throws {
        let descriptor = try #require(DestinationRegistry.destination(id: "runtimeState"))
        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("runtimeState is not a world inspector")
            return
        }
        let providers = FakeWorldProviders()
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers))
                as? RuntimeStatePanelViewController
        )
        panel.loadViewIfNeeded()
        #expect(descriptor.title == "Runtime State")
        #expect(descriptor.section == .world)
        #expect(descriptor.sidebarIdentifier == "Destination-runtimeState")
        #expect(panel.provider === providers)
    }

    /// Accessibility ids are the UI-test API (docs/tools/app-ui.md); pin the
    /// runtime-state set literally.
    @Test @MainActor
    func accessibilityIdentifiersArePinned() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        #expect(panel.inspectSection.sectionIdentifier == "runtimeStateInspect")
        #expect(panel.changeSection.sectionIdentifier == "runtimeStateChange")
        #expect(panel.resetSection.sectionIdentifier == "runtimeStateReset")
        #expect(panel.saveSection.sectionIdentifier == "runtimeStateSave")

        #expect(
            panel.runtimeStateTargetControl.accessibilityIdentifier()
                == "RuntimeStateTargetControl"
        )
        #expect(
            panel.runtimeStateDisableControl.accessibilityIdentifier()
                == "RuntimeStateDisableControl"
        )
        #expect(
            panel.runtimeStateEnableControl.accessibilityIdentifier()
                == "RuntimeStateEnableControl"
        )
        #expect(
            panel.runtimeStateNudgeControl.accessibilityIdentifier() == "RuntimeStateNudgeControl"
        )
        #expect(
            panel.runtimeStateResetTargetControl.accessibilityIdentifier()
                == "RuntimeStateResetTargetControl"
        )
        #expect(
            panel.runtimeStateResetAllControl.accessibilityIdentifier()
                == "RuntimeStateResetAllControl"
        )
        #expect(panel.runtimeStateSlotControl
            .accessibilityIdentifier() == "RuntimeStateSlotControl")
        #expect(panel.runtimeStateSaveControl
            .accessibilityIdentifier() == "RuntimeStateSaveControl")
        #expect(panel.runtimeStateLoadControl
            .accessibilityIdentifier() == "RuntimeStateLoadControl")

        for identifier in [
            "RuntimeStateStatsLabel", "RuntimeStateJournalStatsLabel",
            "RuntimeStateChangeStatsLabel", "RuntimeStateResetStatsLabel",
            "RuntimeStateSaveStatsLabel"
        ] {
            #expect(Self.readout(identifier, in: panel.view) != nil, "\(identifier) is missing")
        }
    }

    @Test @MainActor
    func controlsHaveVisibleFramesInsideDocument() throws {
        let panel = RuntimeStatePanelViewController()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        panel.view.layoutSubtreeIfNeeded()

        let controls: [NSView] = [
            panel.runtimeStateTargetControl,
            panel.runtimeStateDisableControl,
            panel.runtimeStateEnableControl,
            panel.runtimeStateNudgeControl,
            panel.runtimeStateResetTargetControl,
            panel.runtimeStateResetAllControl,
            panel.runtimeStateSlotControl,
            panel.runtimeStateSaveControl,
            panel.runtimeStateLoadControl
        ]
        for control in controls {
            #expect(!control.isHidden)
            #expect(control.frame.height > 0)
            let documentFrame = control.convert(control.bounds, to: scrollView.documentView)
            #expect(scrollView.documentView?.bounds.intersects(documentFrame) == true)
        }
    }

    @Test @MainActor
    func readoutsRenderSnapshotValuesAcrossInspection() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        fake.runtimeStateSnapshot = RuntimeStateSnapshot(
            residentReferenceCount: 42,
            dirtyReferenceCount: 3,
            journalTail: ["1 disable skyrim.esm:00003F", "2 move skyrim.esm:00003F"],
            droppedJournalEntryCount: 7,
            nextJournalSequence: 9,
            currentTargetDescription: "skyrim.esm:00003F"
        )
        fake.runtimeStateSaveSlots = ["autosave", "quick"]
        panel.provider = fake
        panel.startInspecting()
        defer { panel.stopInspecting() }

        #expect(panel.inspectSection.readout.contains("Resident references: 42"))
        #expect(panel.inspectSection.readout.contains("Dirty references: 3"))
        #expect(panel.inspectSection.readout.contains("Next sequence: 9"))
        #expect(panel.inspectSection.readout.contains("Dropped: 7"))
        #expect(panel.inspectSection.journalReadout.contains("1 disable skyrim.esm:00003F"))
        #expect(panel.inspectSection.journalReadout.contains("2 move skyrim.esm:00003F"))
        #expect(panel.changeSection.readout.contains("Current target: skyrim.esm:00003F"))
        #expect(panel.resetSection.readout.contains("Dirty references: 3"))
        #expect(panel.saveSection.readout.contains("Slots: autosave, quick"))
    }

    /// An empty journal and no target read as stated conditions, not as blanks.
    @Test @MainActor
    func emptySnapshotReadsAsStatedConditions() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        panel.provider = fake
        panel.startInspecting()
        defer { panel.stopInspecting() }

        #expect(panel.inspectSection.journalReadout == "No mutations recorded.")
        #expect(panel.changeSection.readout.contains("Current target: no target"))
        #expect(panel.saveSection.readout.contains("Slots: none"))
        #expect(panel.saveSection.readout.contains("Nothing saved or loaded this session."))
    }

    /// A blank FormID field means "the reference I am looking at".
    @Test @MainActor
    func emptyTargetFieldRoutesMutationsToTheCurrentTarget() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        panel.provider = fake

        Self.send(panel.runtimeStateDisableControl)
        Self.send(panel.runtimeStateEnableControl)
        Self.send(panel.runtimeStateNudgeControl)
        Self.send(panel.runtimeStateResetTargetControl)

        #expect(fake.enableCalls.map(\.enabled) == [false, true])
        #expect(fake.enableCalls.allSatisfy { $0.target == .currentTarget })
        #expect(fake.nudgeCalls == [.currentTarget])
        #expect(fake.resetCalls == [.currentTarget])
    }

    /// Typed text is handed to the provider verbatim — parsing it is the
    /// engine's job — and the Reset section reads the same field.
    @Test @MainActor
    func typedFormIDRoutesMutationsToThatReference() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        panel.provider = fake

        panel.runtimeStateTargetControl.stringValue = "  0x00003F  "
        Self.send(panel.runtimeStateDisableControl)
        Self.send(panel.runtimeStateNudgeControl)
        Self.send(panel.runtimeStateResetTargetControl)

        #expect(fake.enableCalls.map(\.target) == [.formID("0x00003F")])
        #expect(fake.nudgeCalls == [.formID("0x00003F")])
        #expect(fake.resetCalls == [.formID("0x00003F")])
    }

    @Test @MainActor
    func changeReadoutStatesWhetherTheMutationApplied() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        panel.provider = fake

        panel.runtimeStateTargetControl.stringValue = "00003F"
        Self.send(panel.runtimeStateDisableControl)
        #expect(panel.changeSection.readout.contains("Applied disable to 00003F."))

        fake.mutationSucceeds = false
        Self.send(panel.runtimeStateNudgeControl)
        #expect(panel.changeSection.readout.contains("No nudge applied: 00003F."))
    }

    @Test @MainActor
    func resetAllReachesTheProviderAndClearsOverriddenState() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        fake.runtimeStateSnapshot = RuntimeStateSnapshot(
            residentReferenceCount: 5,
            dirtyReferenceCount: 2,
            journalTail: [],
            droppedJournalEntryCount: 0,
            nextJournalSequence: 3,
            currentTargetDescription: nil
        )
        panel.provider = fake
        #expect(panel.resetSection.isOverridden)
        #expect(panel.isOverridden)

        Self.send(panel.runtimeStateResetAllControl)
        #expect(fake.resetAllCount == 1)
        #expect(
            panel.resetSection.readout
                .contains("Reset every reference and global to plugin data.")
        )
        #expect(!panel.resetSection.isOverridden)
        #expect(!panel.isOverridden)
    }

    @Test @MainActor
    func saveAndLoadPassTheSlotFieldText() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        panel.provider = fake

        // The field starts on the default slot so the round trip needs no typing.
        #expect(panel.runtimeStateSlotControl.stringValue == RuntimeStateSaveSection
            .defaultSlotName)
        Self.send(panel.runtimeStateSaveControl)
        #expect(fake.savedSlots == ["quick"])
        #expect(panel.saveSection.readout.contains("Saved to quick."))

        panel.runtimeStateSlotControl.stringValue = "before-riverwood"
        Self.send(panel.runtimeStateLoadControl)
        #expect(fake.loadedSlots == ["before-riverwood"])
        #expect(panel.saveSection.readout.contains("Loaded before-riverwood."))

        // An emptied field falls back to the default rather than writing an
        // unnamed file.
        panel.runtimeStateSlotControl.stringValue = "   "
        Self.send(panel.runtimeStateSaveControl)
        #expect(fake.savedSlots == ["quick", "quick"])
    }

    /// A failed save is a data-loss event: the thrown error's own text has to
    /// reach the readout unaltered.
    @Test @MainActor
    func failedOutcomeShowsTheErrorMessageVerbatim() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        panel.provider = fake
        panel.startInspecting()
        defer { panel.stopInspecting() }

        fake.lastSaveOutcome = .failed(
            operation: "save", message: "slot name contains a path separator"
        )
        panel.saveSection.refreshReadout()
        #expect(
            panel.saveSection.readout
                .contains("save failed: slot name contains a path separator")
        )
    }

    @MainActor
    private static func send(_ control: NSControl) {
        control.sendAction(control.action, to: control.target)
    }

    /// Depth-first search for a readout label's text, mirroring the acceptance
    /// harness helper.
    @MainActor
    private static func readout(_ identifier: String, in view: NSView) -> String? {
        if view.accessibilityIdentifier() == identifier, let field = view as? NSTextField {
            return field.stringValue
        }
        for subview in view.subviews {
            if let found = readout(identifier, in: subview) {
                return found
            }
        }
        return nil
    }
}
