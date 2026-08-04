// The shared main-app provider fake (issue #98). Split out of
// DestinationRegistryTests.swift to keep both files inside the lint size caps;
// several panel suites use it, so it is not owned by any one of them.

import AppKit
@testable import opensky

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
    // `timeOfDay` is deliberately not stored here: the live implementation
    // routes it through the same game-clock seam the Runtime State panel uses,
    // so the fake forwards it too (DestinationRegistryRuntimeStateTests).

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

    /// InventoryMenuControlProviding
    var inventoryMenuModel = FakeWorldProviders.makeInventoryMenuModel()
    var inventoryMenuIsOpen = false
    var inventoryMenuMovieEnabled = false
    var inventoryMenuLastAction: String?

    /// ContainerMenuControlProviding (issue #179). The behaviour is in
    /// `FakeWorldProvidersContainerMenu.swift`; only the state lives here,
    /// because an extension cannot hold stored properties.
    var containerMenuModel = ContainerMenuModel(
        mode: .container,
        container: FakeWorldProviders.merchantList,
        player: FakeWorldProviders.playerList,
        pricing: .vanilla,
        containerName: "Test Chest"
    )
    var containerMenuIsOpen = false
    var containerMenuMode = ContainerMenuModel.Mode.container
    var containerMenuMovieEnabled = false
    var containerMenuLastAction: String?
    var containerMenuMerchant: FormID? = FormID(0x0300)

    /// InventoryEquipmentControlProviding (issue #180). One stored value rather
    /// than seven, because this class is at the lint type-length cap; the
    /// behaviour and the type itself are in
    /// `FakeWorldProvidersInventoryEquipment.swift`.
    var inventoryEquipment = FakeInventoryEquipmentState()

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

    /// Footstep director bridges (issue #352), delegated to the shared fake so
    /// both panel fakes record the same way; the forwarding conformance lives
    /// in `FakeFootstepControls.swift`.
    let footsteps = FakeFootstepControls()

    /// RuntimeStateControlProviding (M10.1.5) is delegated to the panel tests'
    /// fake so both suites record mutations through one implementation. The
    /// forwarding conformance lives in the satellite
    /// `DestinationRegistryRuntimeStateTests.swift`, which keeps this file
    /// under the length limit.
    let runtimeState = FakeRuntimeStateProvider()

    /// TriggerControlProviding (issue #173) is delegated the same way; the
    /// forwarding conformance lives in `WorldPanelTests.swift`.
    let triggers = FakeTriggerProvider()

    /// ItemControlProviding (issue #177), delegated for the same reason; the
    /// forwarding conformance lives in `ItemsSectionTests.swift`.
    let items = FakeItemProvider()

    /// ScriptControlProviding (issue #278) is delegated the same way; the
    /// forwarding conformance lives in `DestinationRegistryScriptsTests.swift`.
    let scripts = FakeScriptProvider()

    /// JournalControlProviding (issue #184), delegated for the same reason; the
    /// forwarding conformance lives in `DestinationRegistryJournalTests.swift`.
    let journal = FakeJournalProvider()

    /// PlayerLocomotionControlProviding (issue #188) state; the conformance
    /// lives in `FakeWorldProvidersLocomotion.swift`.
    var locomotion = FakeLocomotionState()
    /// FirstPersonControlProviding (issue #190) state; the conformance lives
    /// beside the locomotion one.
    var firstPerson = FakeFirstPersonState()
}

/// The inventory-menu half of the fake, in an extension so the class body
/// stays inside the lint cap. Stored state remains on the class above.
extension FakeWorldProviders {
    func openInventoryMenu() {
        inventoryMenuIsOpen = true
    }

    func closeInventoryMenu() {
        inventoryMenuIsOpen = false
    }

    func sendInventoryMenuInput(_ event: MenuInputEvent) {
        switch event {
        case .move(.up): inventoryMenuModel.moveSelection(by: -1)
        case .move(.down): inventoryMenuModel.moveSelection(by: 1)
        case .move(.left): inventoryMenuModel.moveCategory(by: -1)
        case .move(.right): inventoryMenuModel.moveCategory(by: 1)
        case .button(.accept): activateInventoryMenuSelection()
        case .button(.cancel): closeInventoryMenu()
        case .pointer: break
        }
    }

    func activateInventoryMenuSelection() {
        inventoryMenuLastAction = inventoryMenuModel.selectedEntry
            .map { "Equipped \($0.name)." }
    }

    func dropInventoryMenuSelection() {
        inventoryMenuLastAction = inventoryMenuModel.selectedEntry
            .map { "Dropped \($0.name)." }
    }

    var inventoryMenuSnapshot: InventoryMenuControlSnapshot {
        InventoryMenuControlSnapshot(
            isOpen: inventoryMenuIsOpen,
            openMenus: inventoryMenuIsOpen ? ["InventoryMenu"] : [],
            worldSimPaused: inventoryMenuIsOpen,
            categoryLabels: inventoryMenuModel.categoryLabels,
            selectedCategoryIndex: inventoryMenuModel.selectedCategoryIndex,
            entryLines: inventoryMenuModel.entries.map(InventoryMenuSection.line(for:)),
            selectedIndex: inventoryMenuModel.selectedIndex,
            carriedWeight: inventoryMenuModel.carriedWeight,
            gold: inventoryMenuModel.gold,
            lastActionText: inventoryMenuLastAction,
            movieEnabled: inventoryMenuMovieEnabled,
            movieLoaded: false,
            movieError: nil,
            movieDrawStats: SWFDrawStats(),
            movieFaults: 0,
            movieMissingNames: 0,
            movieUnhandledInvokes: 0,
            movieEntryTitles: [],
            movieCategoryTitles: []
        )
    }
}

/// The system-menu half of the fake, likewise in an extension.
extension FakeWorldProviders {
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
}
