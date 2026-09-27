// M10.1 milestone acceptance (issue #162). Drives the whole
// World > Runtime State gate sentence — inspect the live store, change a
// reference, reset it, save the world state and read it back — through the real
// shell types: the destination registry, the sidebar view controller, the
// registry's own panel factory, and the controls a user clicks. The only
// stand-in on this side is `FakeWorldProviders`, the same provider surface the
// game controller implements.
//
// The engine half of the gate is in `M10StateAcceptanceEngineTests.swift`, the
// satellite of this suite, and it uses no fakes at all: a real
// `WorldStateStore`, a real `CellStreamer` and a real `OpenSkySaveStore` prove
// that a mutation survives a streaming boundary and a save round trip.
//
// `make test-ui` is blocked on the development machine (TCC harness init), so
// this unit-level test is the deterministic evidence for the gate. Readouts are
// read back by accessibility identifier out of the built view hierarchy, which
// also pins those identifiers as the UI-test contract. No game data is involved
// anywhere: a save is OpenSky's own format and every fixture is built in code.

import AppKit
import Foundation
@testable import opensky
import Testing

struct M10StateAcceptanceTests {
    // MARK: Step 1 — select World > Runtime State

    /// The destination resolves, reports itself through the sidebar's selection
    /// callback, builds `RuntimeStatePanelViewController` through the registry
    /// factory, and the readouts render the engine's snapshot.
    @Test @MainActor
    func selectingRuntimeStateBuildsThePanelAndRendersTheSnapshot() throws {
        let harness = M10AcceptanceHarness()
        let descriptor = try #require(DestinationRegistry.destination(id: "runtimeState"))
        #expect(descriptor.sidebarIdentifier == "Destination-runtimeState")
        #expect(descriptor.title == "Runtime State")

        let panel = try harness.selectRuntimeState(Self.liveSnapshot)
        #expect(harness.selectedDestinationID == "runtimeState")

        let stats = try #require(harness.readout("RuntimeStateStatsLabel", in: panel))
        #expect(stats.contains("Resident references: 118"))
        #expect(stats.contains("Dirty references: 2"))
        #expect(stats.contains("Next sequence: 5"))
        #expect(stats.contains("Dropped: 0"))

        let journal = try #require(harness.readout("RuntimeStateJournalStatsLabel", in: panel))
        #expect(journal.contains("3 set enableState skyrim.esm:000200"))
        #expect(journal.contains("4 set transform skyrim.esm:000201"))
    }

    // MARK: Step 2 — change a reference through the panel

    /// Disable and Nudge carry the typed FormID to the engine, the dirty count
    /// follows into both the Reset readout and the sidebar's override dot, and
    /// Reset all clears them together.
    @Test @MainActor
    func changingAReferenceReachesTheEngineAndLightsTheSidebar() throws {
        let harness = M10AcceptanceHarness()
        let panel = try harness.selectRuntimeState()
        #expect(harness.overrideIndicatorIsVisible("runtimeState") == false)

        panel.runtimeStateTargetControl.stringValue = "000200"
        sendM10Control(panel.runtimeStateDisableControl)
        sendM10Control(panel.runtimeStateNudgeControl)
        #expect(harness.engine.enableCalls.map(\.enabled) == [false])
        #expect(harness.engine.enableCalls.map(\.target) == [.formID("000200")])
        #expect(harness.engine.nudgeCalls == [.formID("000200")])
        #expect(panel.changeSection.readout.contains("Applied nudge to 000200."))

        // The engine now reports what those two mutations did to the store.
        harness.reportDirtyCount(2)
        harness.refresh(panel)
        #expect(panel.resetSection.readout.contains("Dirty references: 2"))
        #expect(harness.overrideIndicatorIsVisible("runtimeState") == true)

        sendM10Control(panel.runtimeStateResetAllControl)
        harness.refresh(panel)
        #expect(harness.engine.resetAllCount == 1)
        #expect(panel.resetSection.readout
            .contains("Reset every reference and global to plugin data."))
        #expect(panel.resetSection.readout.contains("Dirty references: 0"))
        #expect(harness.overrideIndicatorIsVisible("runtimeState") == false)
    }

    /// Reset target acts on the same field the Change section owns, so the two
    /// sections can never disagree about which reference is selected.
    @Test @MainActor
    func resetTargetActsOnTheChangeSectionsReference() throws {
        let harness = M10AcceptanceHarness()
        let panel = try harness.selectRuntimeState()

        panel.runtimeStateTargetControl.stringValue = "0x000201"
        sendM10Control(panel.runtimeStateResetTargetControl)
        #expect(harness.engine.resetCalls == [.formID("0x000201")])
        #expect(panel.resetSection.readout.contains("Reset 0x000201."))
    }

    // MARK: Step 3 — save and load through the panel

    /// Both buttons pass the slot field's text, and the readout names the slot
    /// and lists what is on disk.
    @Test @MainActor
    func savingAndLoadingThroughThePanelPassesTheSlot() throws {
        let harness = M10AcceptanceHarness()
        harness.engine.runtimeStateSaveSlots = ["autosave", "quick"]
        let panel = try harness.selectRuntimeState(Self.liveSnapshot)
        #expect(panel.runtimeStateSlotControl.stringValue == RuntimeStateSaveSection
            .defaultSlotName)

        sendM10Control(panel.runtimeStateSaveControl)
        #expect(harness.engine.savedSlots == ["quick"])
        let saved = try #require(harness.readout("RuntimeStateSaveStatsLabel", in: panel))
        #expect(saved.contains("Saved to quick."))
        #expect(saved.contains("Slots: autosave, quick"))

        panel.runtimeStateSlotControl.stringValue = "m10-acceptance"
        sendM10Control(panel.runtimeStateLoadControl)
        #expect(harness.engine.loadedSlots == ["m10-acceptance"])
        #expect(harness.readout("RuntimeStateSaveStatsLabel", in: panel)?
            .contains("Loaded m10-acceptance.") == true)
    }

    // MARK: Step 4 — a corrupt save is surfaced, not swallowed

    /// Byte-level corruption in a slot file is reported as a typed
    /// `OpenSkySaveError` by the store, and a missing slot as an
    /// `OpenSkySaveStoreError`. Nothing crashes and nothing decodes.
    @Test
    func corruptSlotFilesSurfaceTypedErrorsFromTheStore() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OpenSkySaveStore(directory: directory)
        let valid = OpenSkySaveFixture.encodedRichSave()

        try Self.write(
            OpenSkySaveFixture.patching(valid, at: 0, with: Array("BAD!".utf8)),
            toSlot: "bad-magic", in: store
        )
        #expect(throws: OpenSkySaveError.badMagic) {
            try store.load(slot: "bad-magic")
        }

        try Self.write(
            OpenSkySaveFixture.truncating(valid, to: 10), toSlot: "truncated", in: store
        )
        #expect(throws: OpenSkySaveError.self) {
            try store.load(slot: "truncated")
        }

        #expect(throws: OpenSkySaveStoreError.slotNotFound("never-written")) {
            try store.load(slot: "never-written")
        }

        // An intact file beside them still reads, so the failures above are
        // about those bytes and not about the directory.
        try Self.write(valid, toSlot: "intact", in: store)
        let file = try store.load(slot: "intact")
        #expect(file.snapshot == OpenSkySaveFixture.richSnapshot())
        let slots = try store.listSlots()
        #expect(slots == ["bad-magic", "intact", "truncated"])
    }

    /// A failed load is a data-loss event: the thrown error's own text has to
    /// reach `RuntimeStateSaveStatsLabel` unaltered, because that readout is
    /// what makes a failure diagnosable from a screenshot.
    @Test @MainActor
    func aFailedLoadShowsTheTypedErrorMessageVerbatim() throws {
        let harness = M10AcceptanceHarness()
        let panel = try harness.selectRuntimeState()
        let message = String(describing: OpenSkySaveError.badMagic)

        harness.engine.lastSaveOutcome = .failed(operation: "load", message: message)
        harness.refresh(panel)
        let readout = try #require(harness.readout("RuntimeStateSaveStatsLabel", in: panel))
        #expect(readout.contains("load failed: \(message)"))

        let mismatch = String(
            describing: OpenSkySaveError.fingerprintMismatch(
                reason: "plugin 'Dawnguard.esm' is loaded now but was not loaded then"
            )
        )
        harness.engine.lastSaveOutcome = .failed(operation: "load", message: mismatch)
        harness.refresh(panel)
        #expect(harness.readout("RuntimeStateSaveStatsLabel", in: panel)?
            .contains("load failed: \(mismatch)") == true)
    }

    // MARK: The gate — one uninterrupted session

    /// The panel half of the M10.1 gate in one session, in the order a user
    /// performs it, on a single provider set: select World > Runtime State,
    /// inspect the store, disable and nudge a reference, save the slot, load it
    /// back, and reset everything to plugin data.
    @Test @MainActor
    func acceptanceFlowRunsEndToEndOnOneProviderSet() throws {
        let harness = M10AcceptanceHarness()
        let panel = try harness.selectRuntimeState(Self.liveSnapshot)
        #expect(harness.selectedDestinationID == "runtimeState")
        #expect(harness.overrideIndicatorIsVisible("runtimeState") == true)

        panel.runtimeStateTargetControl.stringValue = "000200"
        sendM10Control(panel.runtimeStateDisableControl)
        sendM10Control(panel.runtimeStateNudgeControl)

        panel.runtimeStateSlotControl.stringValue = "m10-acceptance"
        sendM10Control(panel.runtimeStateSaveControl)
        sendM10Control(panel.runtimeStateLoadControl)
        harness.refresh(panel)

        sendM10Control(panel.runtimeStateResetAllControl)
        harness.refresh(panel)

        #expect(harness.engine.enableCalls.map(\.enabled) == [false])
        #expect(harness.engine.nudgeCalls == [.formID("000200")])
        #expect(harness.engine.savedSlots == ["m10-acceptance"])
        #expect(harness.engine.loadedSlots == ["m10-acceptance"])
        #expect(harness.engine.resetAllCount == 1)
        #expect(harness.overrideIndicatorIsVisible("runtimeState") == false)
        #expect(harness.readout("RuntimeStateStatsLabel", in: panel)?
            .contains("Dirty references: 0") == true)
    }

    // MARK: Synthetic engine state

    /// What a live session reports after two mutations: invented counts and
    /// preformatted journal lines, no game data.
    private static let liveSnapshot = RuntimeStateSnapshot(
        residentReferenceCount: 118,
        dirtyReferenceCount: 2,
        journalTail: [
            "3 set enableState skyrim.esm:000200",
            "4 set transform skyrim.esm:000201"
        ],
        droppedJournalEntryCount: 0,
        nextJournalSequence: 5,
        currentTargetDescription: "skyrim.esm:000200"
    )

    static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "opensky-m10-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func write(
        _ data: Data,
        toSlot slot: String,
        in store: OpenSkySaveStore
    ) throws {
        try data.write(to: store.url(forSlot: slot))
    }
}
