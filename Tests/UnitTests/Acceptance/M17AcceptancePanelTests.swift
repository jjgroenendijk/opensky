// M17 milestone panel acceptance (issue #209): one uninterrupted run through
// the real sidebar model and the registry-built World > Dialogue & Voice panel
// on a single provider set, in the M10-M16 acceptance-triad shape.
//
// The readouts are found by their accessibility identifiers, which is the
// deterministic substitute while UI automation is TCC-blocked
// (docs/tools/environment.md). What this adds over the section suites is that
// the whole destination works as one surface, in the order a conversation uses
// it — open it, read the list and the trace, look at the framing, play the
// line, watch the mouth, leave — without a single fake being swapped halfway.

import AppKit
@testable import opensky
import Testing

@MainActor
struct M17AcceptancePanelTests {
    @Test
    func theDialogueDestinationRunsTheWholeAcceptanceFlow() throws {
        let providers = FakeWorldProviders()
        providers.dialogue.snapshot = Self.dialogue
        providers.dialogueCamera.snapshot = Self.camera
        providers.faceMorphSnapshot = Self.faceMorphs
        providers.voice.paths = Self.voicePaths
        providers.voice.currentDescription = Self.voiceLine
        providers.voice.playbackDescription = "Position: 1.42 / 3.10 s"
        providers.voice.lipSyncSnapshot = Self.lipSync
        providers.audioStatsSnapshot = Self.audioStats

        let panel = try Self.buildPanel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        Self.expectEveryReadout(panel)
        Self.driveTheConversation(panel, providers: providers)
        Self.frameTheSpeaker(panel, providers: providers)
        Self.playTheLine(panel, providers: providers)
        Self.moveTheFace(panel, providers: providers)
        try Self.resetTheDestination(panel, providers: providers)
    }

    // MARK: - The run

    /// The sidebar row and the registry factory, taken through the same path
    /// the app takes rather than by constructing the panel directly.
    private static func buildPanel(
        providers: FakeWorldProviders
    ) throws -> DialoguePanelViewController {
        let worldGroup = try #require(
            AppSidebarModel.groups().first { $0.section == .world }
        )
        let descriptor = try #require(
            worldGroup.destinations.first { $0.id == "dialogueVoice" }
        )
        #expect(descriptor.sidebarIdentifier == "Destination-dialogueVoice")
        #expect(descriptor.title == "Dialogue & Voice")

        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("World > Dialogue & Voice is not a world inspector")
            throw M17PanelAcceptanceError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers))
                as? DialoguePanelViewController
        )
        panel.loadViewIfNeeded()
        return panel
    }

    /// Every readout the destination publishes, read back by accessibility id.
    /// A conversation in progress has to be legible in all six.
    private static func expectEveryReadout(_ panel: DialoguePanelViewController) {
        let view = panel.view
        #expect(scriptsReadout("DialogueTopicsStatsLabel", in: view)?
            .contains("Conversation: Belethor") == true)
        #expect(scriptsReadout("DialogueTopicsStatsLabel", in: view)?
            .contains("world running") == true)
        #expect(scriptsReadout("DialogueConditionsStatsLabel", in: view)?
            .contains("conditions failed") == true)
        #expect(scriptsReadout("DialogueMovieStatsLabel", in: view)?
            .contains("Movie") == true)
        #expect(scriptsReadout("DialogueCameraStatsLabel", in: view)?
            .contains("engaged") == true)
        #expect(scriptsReadout("DialogueCameraSpeakerStatsLabel", in: view)?
            .contains("facing the player") == true)
        #expect(scriptsReadout("DialogueCameraSpeakerStatsLabel", in: view)?
            .contains("M17ShopkeeperSandbox suspended") == true)
        #expect(scriptsReadout("AudioVoiceStatsLabel", in: view)?
            .contains("Position: 1.42 / 3.10 s") == true)
        #expect(scriptsReadout("VoiceSourceStatsLabel", in: view)?
            .contains("Voice submix: 1 source(s)") == true)
        #expect(scriptsReadout("LipSyncStatsLabel", in: view)?
            .contains("Aah 0.75") == true)
        #expect(scriptsReadout("FaceMorphStatsLabel", in: view)?
            .contains("2 targets") == true)
    }

    /// Step 1 — the conversation itself. Open, move the cursor, choose and
    /// leave all reach the same engine entry points the live keys do.
    private static func driveTheConversation(
        _ panel: DialoguePanelViewController,
        providers: FakeWorldProviders
    ) {
        sendScriptsControl(panel.dialogueOpenControl)
        #expect(providers.dialogue.openCount == 1)

        sendScriptsControl(panel.dialogueSection.downControl)
        sendScriptsControl(panel.dialogueSection.upControl)
        sendScriptsControl(panel.dialogueChooseControl)
        #expect(providers.dialogue.events == [.move(.down), .move(.up), .button(.accept)])
    }

    /// Step 2 — the camera. Forcing it and drawing its gizmo are the two
    /// switches that make the framing checkable without a conversation.
    private static func frameTheSpeaker(
        _ panel: DialoguePanelViewController,
        providers: FakeWorldProviders
    ) {
        let section = panel.dialogueCameraSection
        section.forceControl.state = .on
        sendScriptsControl(section.forceControl)
        #expect(providers.isDialogueCameraForced)

        section.overlayControl.state = .on
        sendScriptsControl(section.overlayControl)
        #expect(providers.dialogueCameraOverlayEnabled)

        let index = DialogueCameraSection.targets.firstIndex(of: .nearestActor) ?? 0
        section.targetControl.selectItem(at: index)
        sendScriptsControl(section.targetControl)
        #expect(providers.dialogueCameraTarget == .nearestActor)
    }

    /// Step 3 — the voice line. The filter narrows the corpus, the picker lists
    /// what matched, and Play reaches the provider with the path it listed.
    private static func playTheLine(
        _ panel: DialoguePanelViewController,
        providers: FakeWorldProviders
    ) {
        panel.audioVoiceFilterControl.stringValue = "femaleeventoned"
        sendScriptsControl(panel.voiceSection.applyFilterControl)
        #expect(providers.voiceFileFilter == "femaleeventoned")
        #expect(panel.audioVoiceFileControl.itemTitles == providers.selectableVoiceFileNames)

        panel.audioVoiceFileControl.selectItem(at: 0)
        sendScriptsControl(panel.audioVoicePlayControl)
        #expect(providers.playedVoiceFileNames == [providers.selectableVoiceFileNames[0]])
    }

    /// Step 4 — the face. One named target, one weight, and the reset beside
    /// it: the A/B seam a lip-sync capture is compared across.
    private static func moveTheFace(
        _ panel: DialoguePanelViewController,
        providers: FakeWorldProviders
    ) {
        panel.faceMorphTargetControl.selectItem(withTitle: "Aah")
        sendScriptsControl(panel.faceMorphTargetControl)
        panel.morphWeightControl.floatValue = 0.5
        sendScriptsControl(panel.morphWeightControl)
        #expect(providers.faceMorphSnapshot.weights["Aah"] == 0.5)

        sendScriptsControl(panel.faceMorphSection.resetControl)
        #expect(providers.faceMorphSnapshot.weights.isEmpty)
    }

    /// Step 5 — the destination's override policy. An open conversation, a
    /// forced camera, a scrubbed weight and lip sync switched off all light the
    /// sidebar dot, and the sidebar's own reset — not the panel's controls —
    /// puts every one of them back.
    private static func resetTheDestination(
        _ panel: DialoguePanelViewController,
        providers: FakeWorldProviders
    ) throws {
        let descriptor = try #require(DestinationRegistry.destination(id: "dialogueVoice"))
        let context = WorldPanelContext(providers: providers)
        let overrides = try #require(descriptor.overrides)
        #expect(overrides.isOverridden(context), "a forced camera must light the dot")

        panel.lipSyncEnabledControl.state = .off
        sendScriptsControl(panel.lipSyncEnabledControl)
        #expect(!providers.lipSyncEnabled)

        overrides.resetToDefaults(context)
        #expect(providers.lipSyncEnabled)
        #expect(!providers.isDialogueCameraForced)
        #expect(!providers.dialogueCameraOverlayEnabled)
        // Leaving the conversation is part of the reset, because an open
        // conversation holds the engine menu stack. The fake records the
        // request rather than acting on it — closing a conversation is the live
        // controller's own state machine — so the assertion is that the reset
        // asked, which is the contract the registry owns.
        #expect(providers.dialogue.closeCount == 1)
        // What the session played is not undone by a reset: it happened.
        #expect(providers.playedVoiceFileNames.count == 1)
    }

    // MARK: - Fixtures

    private static let speakerKey = ReferenceKey.generated(1)

    private static let dialogue = makeDialogueSnapshot(
        topicCount: 15037,
        infoCount: 31465,
        targetName: "Belethor",
        targetKey: speakerKey,
        speaker: "Belethor",
        isOpen: true,
        openMenus: ["Dialogue Menu"],
        worldSimPaused: false,
        state: "topicList",
        rows: [
            DialogueTopicRow(
                topic: FormID(0x1701), info: FormID(0x1711),
                text: "I will help you.", endsConversation: false
            ),
            DialogueTopicRow(
                topic: FormID(0x1703), info: FormID(0x1713),
                text: "Farewell.", endsConversation: true
            )
        ],
        selectedIndex: 0,
        subtitle: "Then it is begun.",
        rejections: [DialogueRejectionRow(
            topic: FormID(0x1702), reasons: ["conditions failed"]
        )],
        unresolvedConditionCount: 0,
        lastOutcome: "opened with Belethor: 2 topics, 1 rejected"
    )

    private static let camera = makeDialogueCameraSnapshot(
        isEngaged: true,
        speakerName: "Belethor",
        speakerKey: speakerKey,
        pose: makeDialogueCameraPose(),
        speakerFocus: DialogueSpeakerFocusRow(
            movementState: "stopped",
            yawDegrees: 178.5,
            targetYawDegrees: 180,
            isSettled: true,
            isPackageSuspended: true,
            packageEditorID: "M17ShopkeeperSandbox"
        ),
        lastOutcome: "Dialogue camera: engaged on Belethor."
    )

    private static let faceMorphs = FaceMorphControlSnapshot(
        actor: FormID(0x1720),
        targetNames: ["Aah", "BigAah"],
        weights: [:],
        pairedPaths: ["actors\\character\\facegendata\\facegeom\\m17.tri"],
        associationMisses: [],
        unknownTargetCount: 0
    )

    private static let voiceLine =
        "femaleeventoned\\m17line_000c7917_1.fuz — 3.10 s, 1728 lip bytes"

    private static let voicePaths = [
        "sound\\voice\\opensky.esm\\femaleeventoned\\m17line_000c7917_1.fuz",
        "sound\\voice\\opensky.esm\\femaleeventoned\\m17line_000c7918_1.fuz"
    ]

    private static let lipSync = LipSyncSnapshot(
        actor: FormID(0x1720),
        activeLine: "femaleeventoned\\m17line_000c7917_1.fuz",
        trackTime: 1.42,
        clockMode: .audio,
        liveWeights: ["Aah": 0.75],
        unmappedActiveSlots: [],
        isDecaying: false,
        layout: "header 24 B · tuple 3 · vocab 16 · 33 slots/frame"
    )

    private static let audioStats = AudioStatsSnapshot(
        enabled: true,
        engineRunning: true,
        outputDescription: "48000 Hz stereo",
        sources: [AudioSourceStatsSnapshot(
            name: "sound\\voice\\opensky.esm\\femaleeventoned\\m17line_000c7917_1.fuz",
            categoryName: AudioCategory.voice.displayName,
            isPositional: true,
            worldPosition: SIMD3(180, 0, 0),
            distanceMeters: 1.4,
            fadeGain: 1,
            isFading: false,
            effectiveGain: 0.8,
            positionSeconds: 1.42
        )],
        sourceCap: 32
    )
}

/// Thrown only to end the run early when the registry hands back something
/// other than a world inspector, which `Issue.record` has already reported.
private enum M17PanelAcceptanceError: Error {
    case notAWorldInspector
}
