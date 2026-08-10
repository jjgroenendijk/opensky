// M9 milestone acceptance (issue #157). Drives the whole World > Audio gate
// sentence — mute and solo categories, inspect sources, trigger a selected
// sound, force a track, toggle SFX and ambience — through the real shell types:
// the destination registry, the sidebar view controller, the registry's own
// panel factory, and the controls a user clicks. The only stand-in is
// `FakeWorldProviders` (shared with the other panel tests), which is the same
// provider surface the game controller implements.
//
// `make test-ui` is blocked on the development machine (TCC harness init), so
// this unit-level test is the deterministic evidence for the gate. Readouts are
// read back by accessibility identifier out of the built view hierarchy, which
// also pins those identifiers as the UI-test contract. No game data, no audio
// device and no rendered frames are involved; the audible half of the gate is
// the human step written down in docs/engine/world-sfx.md and
// docs/engine/music.md, and the real-install half is
// `M9AudioAcceptanceRealDataTests`.

import AppKit
@testable import opensky
import Testing

/// One M9 acceptance session: the provider set the panel binds to, the real
/// sidebar, and the registry factory that builds the Audio destination's panel.
@MainActor
private final class M9AcceptanceHarness {
    let providers = FakeWorldProviders()
    let sidebar = AppSidebarViewController()

    /// Last destination the sidebar reported through the shell's own callback.
    private(set) var selectedDestinationID: String?

    var context: WorldPanelContext {
        WorldPanelContext(providers: providers)
    }

    init() {
        sidebar.onSelect = { [weak self] descriptor in
            self?.selectedDestinationID = descriptor.id
        }
        sidebar.isDestinationOverridden = { [weak self] id in
            guard let self else { return false }
            return DestinationRegistry.destination(id: id)?
                .overrides?.isOverridden(context) ?? false
        }
        _ = sidebar.view
    }

    /// Selects the sidebar row and builds that destination's panel through the
    /// registry factory, exactly as the shell does on selection.
    func select(_ id: String) -> (any InspectorPanel)? {
        sidebar.select(id: id)
        guard
            case let .worldInspector(makePanel) = DestinationRegistry.destination(id: id)?.content
        else { return nil }
        let panel = makePanel(context)
        panel.loadViewIfNeeded()
        refresh(panel)
        return panel
    }

    /// Builds the Audio panel and puts the engine in the state the readouts
    /// describe once a user has ticked `AudioEnabledControl`.
    func selectAudioAndEnable() throws -> AudioPanelViewController {
        let panel = try #require(select("audio") as? AudioPanelViewController)
        panel.audioEnabledControl.state = .on
        send(panel.audioEnabledControl)
        providers.audioStatsSnapshot = Self.runningSnapshot(sources: [])
        refresh(panel)
        return panel
    }

    /// Runs one inspection pass (sync controls, refresh readouts) without
    /// leaving the 2 Hz ticker running, so assertions stay deterministic.
    func refresh(_ panel: any InspectorPanel) {
        panel.startInspecting()
        panel.stopInspecting()
    }

    func overrideIndicatorIsVisible(_ id: String) -> Bool? {
        sidebar.refreshOverrideIndicators()
        return sidebar.overrideIndicatorIsVisible(destinationID: id)
    }

    /// Text of the readout label carrying `identifier`, found in the built
    /// panel; nil when no such label is on screen.
    func readout(_ identifier: String, in panel: any InspectorPanel) -> String? {
        Self.label(identifier, in: panel.view)
    }

    /// What the engine publishes once it is enabled and running, with whatever
    /// sources the case under test wants listed.
    static func runningSnapshot(
        sources: [AudioSourceStatsSnapshot]
    ) -> AudioStatsSnapshot {
        AudioStatsSnapshot(
            enabled: true,
            engineRunning: true,
            outputDescription: "44100 Hz, 2 ch",
            sources: sources,
            sourceCap: WorldAudioEngine.maxConcurrentSources
        )
    }

    @MainActor
    private static func label(_ identifier: String, in view: NSView) -> String? {
        if view.accessibilityIdentifier() == identifier, let field = view as? NSTextField {
            return field.stringValue
        }
        for subview in view.subviews {
            if let found = label(identifier, in: subview) {
                return found
            }
        }
        return nil
    }
}

@MainActor
private func send(_ control: NSControl) {
    control.sendAction(control.action, to: control.target)
}

struct M9AcceptanceTests {
    // MARK: Step 1 — select World > Audio and start the engine

    /// The Audio destination resolves, reports itself through the sidebar's
    /// selection callback, and builds the panel whose output readout follows the
    /// engine from disabled to running.
    @Test @MainActor
    func selectingAudioBuildsThePanelAndStartsTheEngine() throws {
        let harness = M9AcceptanceHarness()
        let descriptor = try #require(DestinationRegistry.destination(id: "audio"))
        #expect(descriptor.sidebarIdentifier == "Destination-audio")

        let panel = try #require(harness.select("audio") as? AudioPanelViewController)
        #expect(harness.selectedDestinationID == "audio")
        let disabled = try #require(harness.readout("AudioStatsLabel", in: panel))
        #expect(disabled.contains("Audio: disabled"))

        panel.audioEnabledControl.state = .on
        send(panel.audioEnabledControl)
        #expect(harness.providers.audioEnabled)
        harness.providers.audioStatsSnapshot = M9AcceptanceHarness.runningSnapshot(sources: [])
        harness.refresh(panel)
        let running = try #require(harness.readout("AudioStatsLabel", in: panel))
        #expect(running.contains("Audio: running"))
        #expect(running.contains("Output: 44100 Hz, 2 ch"))
    }

    // MARK: Step 2 — mute and solo a category

    /// Muting one category and soloing another writes both to the provider,
    /// shows them on the routing line of `AudioStatsLabel`, and lights the
    /// sidebar's override dot until the destination reset clears it.
    @Test @MainActor
    func mutingAndSoloingCategoriesShowsInTheReadoutAndSidebar() throws {
        let harness = M9AcceptanceHarness()
        let panel = try harness.selectAudioAndEnable()
        try Self.muteAndSolo(harness, panel)

        DestinationRegistry.destination(id: "audio")?.overrides?
            .resetToDefaults(harness.context)
        harness.refresh(panel)
        #expect(harness.providers.soloedAudioCategory == nil)
        #expect(!harness.providers.audioCategoryIsMuted(.effects))
        #expect(harness.overrideIndicatorIsVisible("audio") == false)
        let cleared = try #require(harness.readout("AudioStatsLabel", in: panel))
        #expect(cleared.contains("Mute: none  Solo: none"))
    }

    // MARK: Step 3 — inspect the live sources

    /// The Sources readout lists every live source in the documented per-source
    /// format, under the cap the engine publishes.
    @Test @MainActor
    func sourceListReportsEveryLiveSource() throws {
        let harness = M9AcceptanceHarness()
        let panel = try harness.selectAudioAndEnable()
        harness.providers.audioStatsSnapshot = M9AcceptanceHarness.runningSnapshot(
            sources: [Self.doorSource, Self.ambienceSource]
        )
        harness.refresh(panel)

        let readout = try #require(harness.readout("AudioSourcesStatsLabel", in: panel))
        #expect(readout.contains("Sources: 2 / 8"))
        #expect(readout.contains("doorwoodopen.xwm [effects] 700, 0, 0 | 10.0 m | gain 1.00"))
        #expect(readout.contains("wind.xwm [effects] 0, 0, 0 | 0.0 m | gain 0.50"))
        #expect(!readout.contains("Play failed"))
    }

    // MARK: Step 4 — trigger the selected sound

    /// Picking a file and pressing Play reaches the provider and the new source
    /// appears in the readout on the next inspection pass.
    @Test @MainActor
    func triggeringTheSelectedSoundReachesTheProviderAndReadout() throws {
        let harness = M9AcceptanceHarness()
        harness.providers.selectableAudioFileNames = Self.selectableFiles
        let panel = try harness.selectAudioAndEnable()
        try Self.playSelectedFile(harness, panel)

        send(panel.audioStopAllControl)
        #expect(harness.providers.stopAllAudioSourcesCount == 1)
    }

    // MARK: Step 5 — force a music playlist

    /// The Music picker offers the automatic entry ahead of the MUSC list,
    /// forcing one reaches the director, and the readout names state and track.
    @Test @MainActor
    func forcingAMusicPlaylistReachesTheProviderAndReadout() throws {
        let harness = M9AcceptanceHarness()
        harness.providers.selectableMusicTypeNames = Self.selectableMusicTypes
        let panel = try harness.selectAudioAndEnable()
        try Self.forceTownPlaylist(harness, panel)

        send(panel.audioStopMusicControl)
        harness.refresh(panel)
        #expect(harness.providers.stopMusicCount == 1)
        let stopped = try #require(harness.readout("AudioMusicStatsLabel", in: panel))
        #expect(stopped.contains("Music: none"))
    }

    // MARK: Step 6 — SFX and ambience toggles

    /// Both director toggles round-trip through the provider, the readout names
    /// the last SFX and the current bed, and switching one off is an override.
    @Test @MainActor
    func sfxAndAmbienceTogglesReachTheProviderAndReadout() throws {
        let harness = M9AcceptanceHarness()
        let panel = try harness.selectAudioAndEnable()
        harness.providers.lastSFXDescription = "sound\\fx\\dor\\doorwoodopen.xwm"
        harness.providers.currentAmbienceDescription = "0x0001AABB"
        harness.refresh(panel)
        let readout = try #require(harness.readout("AudioSfxStatsLabel", in: panel))
        #expect(readout.contains("SFX: sound\\fx\\dor\\doorwoodopen.xwm"))
        #expect(readout.contains("Ambience: 0x0001AABB"))

        try Self.toggleSFXOff(harness, panel)

        send(panel.sfxSection.stopAmbienceControl)
        harness.refresh(panel)
        #expect(harness.providers.stopAmbienceCount == 1)
        #expect(harness.readout("AudioSfxStatsLabel", in: panel)?
            .contains("Ambience: none") == true)
    }

    // MARK: The gate — one uninterrupted session

    /// The M9 gate in one session, in the order a user performs it, with a
    /// single provider set: select World > Audio, enable the engine, mute and
    /// solo a category, inspect the sources, trigger a selected sound, force a
    /// playlist, and switch the SFX toggle.
    @Test @MainActor
    func acceptanceFlowRunsEndToEndOnOneProviderSet() throws {
        let harness = M9AcceptanceHarness()
        harness.providers.selectableAudioFileNames = Self.selectableFiles
        harness.providers.selectableMusicTypeNames = Self.selectableMusicTypes
        let panel = try harness.selectAudioAndEnable()
        #expect(harness.selectedDestinationID == "audio")

        try Self.muteAndSolo(harness, panel)

        harness.providers.audioStatsSnapshot = M9AcceptanceHarness.runningSnapshot(
            sources: [Self.ambienceSource]
        )
        harness.refresh(panel)
        #expect(harness.readout("AudioSourcesStatsLabel", in: panel)?
            .contains("Sources: 1 / 8") == true)

        try Self.playSelectedFile(harness, panel)
        try Self.forceTownPlaylist(harness, panel)
        try Self.toggleSFXOff(harness, panel)

        // Every change made in the session is still visible at the end of it.
        #expect(harness.providers.soloedAudioCategory == .music)
        #expect(harness.providers.audioCategoryIsMuted(.effects))
        #expect(harness.providers.playedAudioFileNames == [Self.triggeredFile])
        #expect(harness.providers.forcedMusicTypeNames == ["MUSTownWhiterun"])
        #expect(!harness.providers.sfxEnabled)
        #expect(harness.overrideIndicatorIsVisible("audio") == true)
    }

    // MARK: Shared steps

    /// Mutes `effects`, solos `music`, and checks both reached the provider, the
    /// routing line and the sidebar dot.
    @MainActor
    private static func muteAndSolo(
        _ harness: M9AcceptanceHarness, _ panel: AudioPanelViewController
    ) throws {
        let mute = try #require(panel.outputSection.muteControls[.effects])
        mute.state = .on
        send(mute)
        #expect(harness.providers.audioCategoryIsMuted(.effects))

        let solo = try #require(panel.outputSection.soloControls[.music])
        solo.state = .on
        send(solo)
        #expect(harness.providers.soloedAudioCategory == .music)

        harness.refresh(panel)
        let readout = try #require(harness.readout("AudioStatsLabel", in: panel))
        #expect(readout.contains("Mute: Effects  Solo: Music"))
        #expect(harness.overrideIndicatorIsVisible("audio") == true)
    }

    /// Picks the second offered file and presses Play, checking the provider saw
    /// the exact name and the source list grew.
    @MainActor
    private static func playSelectedFile(
        _ harness: M9AcceptanceHarness, _ panel: AudioPanelViewController
    ) throws {
        panel.audioFileControl.selectItem(withTitle: triggeredFile)
        send(panel.audioFileControl)
        let before = harness.providers.audioStatsSnapshot.sources.count
        send(panel.audioPlaySelectedControl)
        #expect(harness.providers.playedAudioFileNames.last == triggeredFile)

        harness.refresh(panel)
        let readout = try #require(harness.readout("AudioSourcesStatsLabel", in: panel))
        #expect(readout.contains("Sources: \(before + 1) / 8"))
        #expect(readout.contains("doorwoodopen.xwm [effects] 700, 0, 0 | 10.0 m | gain 1.00"))
        #expect(!readout.contains("Play failed"))
    }

    /// Forces the town playlist through the picker and checks the provider and
    /// the readout followed.
    @MainActor
    private static func forceTownPlaylist(
        _ harness: M9AcceptanceHarness, _ panel: AudioPanelViewController
    ) throws {
        #expect(panel.audioMusicTypeControl.itemTitles.first == AudioMusicSection.automaticTitle)
        harness.providers.currentMusicStateName = "town"
        panel.audioMusicTypeControl.selectItem(withTitle: "MUSTownWhiterun")
        send(panel.audioMusicTypeControl)
        #expect(harness.providers.forcedMusicTypeNames.last == "MUSTownWhiterun")
        #expect(panel.musicSection.forcedTypeName == "MUSTownWhiterun")

        harness.refresh(panel)
        let readout = try #require(harness.readout("AudioMusicStatsLabel", in: panel))
        #expect(readout.contains("State: town"))
        #expect(readout.contains("Music: MUSTownWhiterun — music\\MUSTownWhiterun.xwm"))
        #expect(!readout.contains("Music error"))
    }

    /// Switches door/activator SFX off and checks the provider took it.
    @MainActor
    private static func toggleSFXOff(
        _ harness: M9AcceptanceHarness, _ panel: AudioPanelViewController
    ) throws {
        let control = panel.sfxSection.sfxEnabledControl
        control.state = .off
        send(control)
        #expect(!harness.providers.sfxEnabled)
        #expect(harness.providers.ambienceEnabled, "the two toggles are independent")

        harness.refresh(panel)
        #expect(control.state == .off)
        #expect(harness.overrideIndicatorIsVisible("audio") == true)
        #expect(harness.readout("AudioSfxStatsLabel", in: panel)?.isEmpty == false)
    }

    // MARK: Synthetic engine state

    /// Files the picker offers. Plausible VFS keys, invented for the test — no
    /// game data is read here.
    private static let selectableFiles = [
        "music\\explore\\mus_explore_atmosphere_02.xwm",
        "sound\\fx\\dor\\doorwoodopen.xwm"
    ]
    private static let triggeredFile = "sound\\fx\\dor\\doorwoodopen.xwm"
    private static let selectableMusicTypes = ["MUSExplore", "MUSTownWhiterun"]

    /// A positional one-shot, as the panel-triggered effect lands.
    private static let doorSource = AudioSourceStatsSnapshot(
        name: triggeredFile,
        categoryName: AudioCategory.effects.rawValue,
        isPositional: true,
        worldPosition: SIMD3<Float>(700, 0, 0),
        distanceMeters: 10,
        fadeGain: 1,
        isFading: false,
        effectiveGain: 1,
        positionSeconds: nil
    )

    /// A half-gain ambience loop, as the director starts a two-entry bed.
    private static let ambienceSource = AudioSourceStatsSnapshot(
        name: "sound\\fx\\amb\\wind.xwm",
        categoryName: AudioCategory.effects.rawValue,
        isPositional: false,
        worldPosition: .zero,
        distanceMeters: 0,
        fadeGain: 1,
        isFading: false,
        effectiveGain: 0.5,
        positionSeconds: nil
    )
}
