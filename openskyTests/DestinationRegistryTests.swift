// The destination registry is the single registration point for main-app
// sidebar destinations (issue #98). These tests pin the UI-test accessibility
// contract (literal ids) as unit assertions — machine-checkable while make
// test-ui is blocked — and verify every world-inspector factory builds a panel.

import AppKit
@testable import opensky
import Testing

/// Stands in for the game controller, which conforms to every provider
/// protocol. Shared with `WorldPanelTests` so a panel test exercises the same
/// wiring the registry factory does, rather than a second partial fake.
@MainActor
final class FakeWorldProviders: WorldControlProviders {
    var refocusCount = 0

    // ShadowControlProviding
    var sunShadowsEnabled = true
    var shadowQuality: ShadowQuality = .high
    var shadowDrawStats = ShadowDrawStats()
    var shadowUpdateMS: Double = 0
    var shadowsActive = true
    func refocusGameView() {
        refocusCount += 1
    }

    /// TerrainLODControlProviding
    var terrainLODConfigurationSnapshot = TerrainLODConfigurationSnapshot(
        configuration: .fallback, source: "test"
    )
    var terrainLODOverrideActive = false
    func applyTerrainLODConfiguration(_: TerrainLODConfiguration) -> Bool {
        terrainLODOverrideActive = true
        return true
    }

    func resetTerrainLODConfiguration() {
        terrainLODOverrideActive = false
    }

    // WeatherControlProviding
    var weatherEnabled = true
    var selectableWeatherNames: [String] = []
    func forceWeather(named name: String?) {
        weatherOverrideActive = name != nil
    }

    func forceWeather(_: WeatherPreset) {
        weatherOverrideActive = true
    }

    var currentWeatherName: String?
    var weatherOverrideActive = false
    var weatherTransitionFraction: Float = 0
    var weatherTransitionsPaused = false
    var windState: WindState = .calm
    var timeOfDay: Float = TimeOfDaySettings.fallback

    // AnimationControlProviding
    var actorAnimationsEnabled = true
    var animationSnapshot = AnimationControlSnapshot(
        playbackCount: 0, updatedBoneCount: 0, updateMS: 0
    )

    // ParticleControlProviding
    var particlesEnabled = true
    var particlesFrozen = false
    var particleEmissionScale: Float = 1
    var particleSnapshot = ParticleControlSnapshot(systemCount: 0, emitterCount: 0, liveCount: 0)

    // PrecipitationControlProviding
    var precipitationEnabled = true
    var precipitationSnapshot = PrecipitationRuntimeSnapshot(
        state: .none, roofOccluded: false, rainLiveCount: 0, snowLiveCount: 0
    )

    // GrassControlProviding
    var grassEnabled = true
    var grassDensityScale: Float = 1
    var grassDrawDistance: Float = GrassRenderPolicy.defaultDrawDistance
    var grassWindScale: Float = 1
    var grassSnapshot = GrassControlSnapshot(
        sceneInstances: 0, drawnInstances: 0, drawCalls: 0, distanceCulledInstances: 0,
        densityCulledInstances: 0, frustumCulledInstances: 0, budgetDroppedInstances: 0
    )

    // HUDControlProviding
    var hudLayerEnabled = true
    var hudCrosshairEnabled = true
    var hudMetersEnabled = true
    var hudCompassEnabled = true
    var hudMarkersEnabled = true
    var hudPromptEnabled = true
    var hudPlaceholderTextEnabled = false
    var hudScale: Float = 1
    var hudControlSnapshot = HUDControlSnapshot(
        isLoaded: false,
        loadError: nil,
        targetReference: nil,
        targetBase: nil,
        targetName: nil,
        targetAction: nil,
        targetDistance: nil,
        targetPosition: nil,
        hitPosition: nil,
        prompt: nil,
        markerHeadings: [],
        cameraHeading: nil,
        scale: 1,
        drawStats: SWFDrawStats()
    )

    // SystemMenuControlProviding
    var systemMenuModel = SystemMenuModel()
    var systemMenuMovieEnabled = false
    var systemMenuMasterVolume: Float = 1
    var systemMenuIsOpen: Bool {
        systemMenuModel.isOpen
    }

    func openSystemMenu() {
        systemMenuModel.open()
    }

    func closeSystemMenu() {
        systemMenuModel.close()
    }

    func sendSystemMenuInput(_ event: MenuInputEvent) {
        systemMenuModel.handle(event)
    }

    var systemMenuSnapshot: SystemMenuControlSnapshot {
        SystemMenuControlSnapshot(
            isOpen: systemMenuModel.isOpen,
            entryTitles: systemMenuModel.entries.map(\.title),
            selectedIndex: systemMenuModel.selectedIndex,
            lastOutcome: systemMenuModel.lastOutcome?.label,
            settingsRevealed: systemMenuModel.settingsRevealed,
            openMenus: systemMenuModel.isOpen ? ["SystemMenu"] : [],
            worldSimPaused: systemMenuModel.isOpen,
            dataRootPath: nil,
            dataRootSource: nil,
            masterVolume: systemMenuMasterVolume,
            audioEnabled: audioEnabled,
            movieEnabled: systemMenuMovieEnabled,
            movieLoaded: false,
            movieError: nil,
            movieDrawStats: SWFDrawStats(),
            movieFaults: 0,
            movieMissingNames: 0,
            movieEntryTitles: [],
            movieState: nil
        )
    }

    // UILabControlProviding
    var uiOverlayEnabled = true
    var uiSampleShown = false
    var uiScale: Float = 1
    var uiSnapshot = UILabControlSnapshot(
        overlayEnabled: true, sampleShown: false, scale: 1, stats: UIDrawStats()
    )
    /// Menu mode runs on the real `MenuModeController`, exactly as
    /// `GameViewControllerUILab` wires it, so a test that pushes a menu
    /// observes the same world-sim pause the engine would report.
    private let menuMode = MenuModeController()

    var menuModeSnapshot: MenuModeControlSnapshot {
        MenuModeControlSnapshot(
            isMenuMode: menuMode.isMenuMode,
            topMenuName: menuMode.topMenu?.name,
            stackDepth: menuMode.stack.count,
            isWorldSimPaused: menuMode.isWorldSimPaused
        )
    }

    func pushPreviewMenu() {
        menuMode.present(MenuIdentifier("UILabMenu\(menuMode.stack.count + 1)"))
    }

    func popPreviewMenu() {
        menuMode.dismissTop()
    }

    func clearPreviewMenus() {
        menuMode.dismissAll()
    }

    var uiLocalizedSampleShown = false
    var localizedLabelsSnapshot = LocalizedLabelsControlSnapshot(
        sampleShown: false, sampleKeyCount: 0, language: "english",
        installLoaded: false, installFileCount: 0, installKeyCount: 0
    )

    // SWFLabControlProviding
    var swfMoviePaths: [String] = []
    var swfLayerEnabled = true
    func selectSWFMovie(path _: String?) {}
    var swfLabSnapshot = SWFLabControlSnapshot(
        selectedPath: nil, layerEnabled: true, loadError: nil, tally: nil,
        unresolvedFontNames: [], drawStats: SWFDrawStats(), installLoaded: false,
        runtime: nil
    )
    func startSWFRuntime() {}
    func advanceSWFRuntime(ticks _: Int) {}
    func stopSWFRuntime() {}
    func sendSWFRuntimeInput(_: SWFInputEvent) {}
    func callSWFRuntimeMovie(_: String) {}
    func clearSWFInvokeLog() {}

    // CameraControlProviding (cameraPoseDescription comes from the protocol
    // extension, deliberately not overridden here).
    var cameraPose = CameraPoseSnapshot.unavailable
    var movementMode = CameraMovementMode.fly
    var movementConfiguration = PlayerMovementConfiguration.synthetic

    /// FrameStatsProviding
    var frameStatsSnapshot = FrameStatsSnapshot.empty

    /// SceneStatsProviding
    var sceneStatsSnapshot = SceneStatsSnapshot.empty

    // AudioControlProviding
    var audioEnabled = false
    var audioMasterVolume: Float = 1
    private var audioCategoryVolumes: [AudioCategory: Float] = [:]
    func audioVolume(for category: AudioCategory) -> Float {
        audioCategoryVolumes[category] ?? 1
    }

    func setAudioVolume(_ volume: Float, for category: AudioCategory) {
        audioCategoryVolumes[category] = volume
    }

    private var mutedAudioCategories: Set<AudioCategory> = []
    var soloedAudioCategory: AudioCategory?
    func audioCategoryIsMuted(_ category: AudioCategory) -> Bool {
        mutedAudioCategories.contains(category)
    }

    func setAudioCategoryMuted(_ muted: Bool, for category: AudioCategory) {
        if muted {
            mutedAudioCategories.insert(category)
        } else {
            mutedAudioCategories.remove(category)
        }
    }

    var selectableAudioFileNames: [String] = []
    /// Files the Sources section asked to play, in order. The M9 acceptance
    /// gate reads this to prove the trigger reached the provider.
    private(set) var playedAudioFileNames: [String] = []
    /// Failure the next `playAudioFile(named:)` reports; nil means success.
    var audioPlayFailure: String?
    /// Mirrors the live bridge: a successful trigger starts one positional
    /// effects source, which the next snapshot then lists.
    func playAudioFile(named name: String) -> String? {
        playedAudioFileNames.append(name)
        guard audioPlayFailure == nil else { return audioPlayFailure }
        audioStatsSnapshot = AudioStatsSnapshot(
            enabled: audioStatsSnapshot.enabled,
            engineRunning: audioStatsSnapshot.engineRunning,
            outputDescription: audioStatsSnapshot.outputDescription,
            sources: audioStatsSnapshot.sources + [
                AudioSourceStatsSnapshot(
                    name: name,
                    categoryName: AudioCategory.effects.rawValue,
                    isPositional: true,
                    worldPosition: SIMD3<Float>(700, 0, 0),
                    distanceMeters: 10,
                    fadeGain: 1,
                    isFading: false,
                    effectiveGain: 1
                )
            ],
            sourceCap: audioStatsSnapshot.sourceCap
        )
        return nil
    }

    private(set) var stopAllAudioSourcesCount = 0
    func stopAllAudioSources() {
        stopAllAudioSourcesCount += 1
    }

    var audioStatsSnapshot = AudioStatsSnapshot.empty

    // World SFX director bridges (M9.2.2).
    var sfxEnabled = true
    var ambienceEnabled = true
    private(set) var stopAmbienceCount = 0
    func stopAmbience() {
        stopAmbienceCount += 1
        currentAmbienceDescription = "none"
    }

    var lastSFXDescription: String?
    var lastSFXError: String?
    var currentAmbienceDescription = "none"

    // Music director bridges (M9.2.3).
    var musicEnabled = true
    var selectableMusicTypeNames: [String] = []
    /// MUSC editor ids the Music section forced, in order.
    private(set) var forcedMusicTypeNames: [String] = []
    /// Failure the next `forceMusicType(named:)` reports; nil means success.
    var musicForceFailure: String?
    /// Mirrors the live bridge: a successful force names the playlist in the
    /// description the readout shows.
    func forceMusicType(named name: String) -> String? {
        forcedMusicTypeNames.append(name)
        guard musicForceFailure == nil else { return musicForceFailure }
        currentMusicDescription = "\(name) — music\\\(name).xwm"
        currentMusicTrackName = "music\\\(name).xwm"
        return nil
    }

    private(set) var stopMusicCount = 0
    func stopMusic() {
        stopMusicCount += 1
        currentMusicDescription = "none"
        currentMusicTrackName = nil
    }

    var currentMusicDescription = "none"
    var currentMusicStateName = "exploration"
    var currentMusicTrackName: String?
    var lastMusicError: String?

    /// RuntimeStateControlProviding (M10.1.5) is delegated to the panel tests'
    /// fake so both suites record mutations through one implementation. The
    /// forwarding conformance lives in the satellite
    /// `DestinationRegistryRuntimeStateTests.swift`, which keeps this file
    /// under the length limit.
    let runtimeState = FakeRuntimeStateProvider()
}

struct DestinationRegistryTests {
    @Test
    func idsAreUnique() {
        let ids = DestinationRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test
    func registryOrderAndIdentifiers() {
        #expect(
            DestinationRegistry.all.map(\.id)
                == [
                    "world", "environment", "hudInteraction", "systemMenu",
                    "audio", "runtimeState", "uiLab", "assetBrowser"
                ]
        )
        // Accessibility identifiers are the UI-test contract; pin them literally.
        #expect(
            DestinationRegistry.all.map(\.sidebarIdentifier) == [
                "Destination-world",
                "Destination-environment",
                "Destination-hudInteraction",
                "Destination-systemMenu",
                "Destination-audio",
                "Destination-runtimeState",
                "Destination-uiLab",
                "Destination-assetBrowser"
            ]
        )
        #expect(
            DestinationRegistry.worldInspectors.map(\.id)
                == [
                    "world", "environment", "hudInteraction", "systemMenu",
                    "audio", "runtimeState", "uiLab"
                ]
        )
        #expect(DestinationRegistry.defaultDestinationID == "world")
    }

    /// No registered destination uses `.viewport` any more — hiding the
    /// inspector column is a View-menu mode, not a sidebar row.
    @Test
    func noRegisteredDestinationUsesBareViewport() {
        for descriptor in DestinationRegistry.all {
            if case .viewport = descriptor.content {
                Issue.record("\(descriptor.id) still registers the bare viewport content")
            }
        }
    }

    @Test
    func gameViewVisibilityPerContentKind() {
        #expect(DestinationRegistry.destination(id: "world")?.showsGameView == true)
        #expect(DestinationRegistry.destination(id: "environment")?.showsGameView == true)
        #expect(DestinationRegistry.destination(id: "hudInteraction")?.showsGameView == true)
        #expect(DestinationRegistry.destination(id: "assetBrowser")?.showsGameView == false)
    }

    @Test @MainActor
    func fullContentFactoryBuildsAController() {
        let context = FullContentContext(gameDataRoot: nil, startupErrorMessage: "test")
        for descriptor in DestinationRegistry.all {
            guard case let .fullContent(makeController) = descriptor.content else { continue }
            let controller = makeController(context)
            // Reload must reach the cached controller in place (Settings flow).
            #expect(controller is any FullContentReloadable)
        }
    }

    @Test @MainActor
    func everyWorldInspectorFactoryBuildsAPanel() {
        let providers = FakeWorldProviders()
        let context = WorldPanelContext(providers: providers)
        for descriptor in DestinationRegistry.worldInspectors {
            guard case let .worldInspector(makePanel) = descriptor.content else {
                Issue.record("\(descriptor.id) is not a world inspector")
                continue
            }
            let panel = makePanel(context)
            panel.loadViewIfNeeded()
            #expect(panel.view.frame.width >= 0)
        }
    }

    @Test @MainActor
    func destinationOverrideActionsTrackAndResetProviders() throws {
        let providers = FakeWorldProviders()
        let context = WorldPanelContext(providers: providers)

        for descriptor in DestinationRegistry.worldInspectors {
            let overrides = try #require(descriptor.overrides)
            #expect(!overrides.isOverridden(context), "\(descriptor.id) is not at defaults")
        }

        providers.movementMode = .walk
        #expect(isOverridden("world", context: context))
        reset("world", context: context)
        #expect(providers.movementMode == .fly)

        providers.grassEnabled = false
        #expect(isOverridden("environment", context: context))
        reset("environment", context: context)
        #expect(providers.grassEnabled)

        providers.hudMetersEnabled = false
        #expect(isOverridden("hudInteraction", context: context))
        reset("hudInteraction", context: context)
        #expect(providers.hudMetersEnabled)

        providers.openSystemMenu()
        #expect(isOverridden("systemMenu", context: context))
        reset("systemMenu", context: context)
        #expect(!providers.systemMenuIsOpen)

        providers.audioEnabled = true
        #expect(isOverridden("audio", context: context))
        reset("audio", context: context)
        #expect(!providers.audioEnabled)

        // M9.2.3: a disabled music director is an audio-destination override,
        // and the destination-level reset re-enables it.
        providers.musicEnabled = false
        #expect(isOverridden("audio", context: context))
        reset("audio", context: context)
        #expect(providers.musicEnabled)

        // M9.2.4: a muted or soloed category is an audio-destination override,
        // and the destination-level reset clears both.
        providers.setAudioCategoryMuted(true, for: .music)
        #expect(isOverridden("audio", context: context))
        reset("audio", context: context)
        #expect(!providers.audioCategoryIsMuted(.music))

        providers.soloedAudioCategory = .voice
        #expect(isOverridden("audio", context: context))
        reset("audio", context: context)
        #expect(providers.soloedAudioCategory == nil)

        providers.uiOverlayEnabled = false
        #expect(isOverridden("uiLab", context: context))
        reset("uiLab", context: context)
        #expect(providers.uiOverlayEnabled)

        #expect(DestinationRegistry.destination(id: "assetBrowser")?.overrides == nil)
    }

    @MainActor
    private func isOverridden(_ id: String, context: WorldPanelContext) -> Bool {
        DestinationRegistry.destination(id: id)?.overrides?.isOverridden(context) ?? false
    }

    @MainActor
    private func reset(_ id: String, context: WorldPanelContext) {
        DestinationRegistry.destination(id: id)?.overrides?.resetToDefaults(context)
    }
}
