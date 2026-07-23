// Hosts the MTKView and wires it to the renderer. Fails soft with an on-screen
// message when the GPU lacks Metal 4 — the engine requires it (AGENTS.md
// "Environment & tech stack"); a missing GPU feature must not crash the app.

import AppKit
import MetalKit
import OSLog
import simd

final class GameViewController: NSViewController {
    enum ScreenshotError: LocalizedError {
        case rendererNotReady

        var errorDescription: String? {
            "World renderer is not ready for a screenshot."
        }
    }

    /// Locator failure shown inside World. Settings remains reachable so the
    /// root can be corrected without relaunching or dismissing an alert loop.
    var startupErrorMessage: String?

    /// Builds the off-main cell provider on the view's Metal device. Set by
    /// the AppDelegate before the window content loads; nil factory or nil
    /// result (missing game data / setup throw) -> no streamer, renderer
    /// falls back to the synthetic DemoScene. The factory runs here (not in
    /// the AppDelegate) because the asset libraries bind GPU resources to the
    /// device the view renders with.
    var cellProviderFactory: ((MTLDevice) -> (any CellSceneProvider)?)?

    /// Thread-safe effective INI/sidebar LOD values shared with the off-main
    /// DistantLODBuilder. AppDelegate replaces this before view load.
    var terrainLODConfigurationStore = TerrainLODConfigurationStore(
        snapshot: TerrainLODConfigurationSnapshot(
            configuration: .fallback,
            source: "safe defaults"
        )
    )

    /// Readable by the UI Lab bridge (GameViewControllerUILab.swift); only this
    /// file assigns it.
    private(set) var renderer: Renderer?
    var canWriteScreenshot: Bool {
        renderer != nil
    }

    /// Retains the streaming controller (and, through it, the build runner +
    /// provider) for the window's lifetime.
    private var streamer: CellStreamer?
    /// Free-fly input shared with the renderer; the view writes it from
    /// NSEvents, the renderer drains it each frame (todo 2.8).
    private let cameraInput = CameraInputState()

    /// Menu-mode source of truth (todo 8.1.2), shared with the input view and
    /// the renderer. Entering menu mode pauses world sim and drops held world
    /// input; leaving it resumes with no time jump. The World > UI Lab preview
    /// (M8.1.4, via GameViewControllerUILab.swift) is the only trigger until
    /// real SWF menus land (M8.2).
    let menuMode = MenuModeController()

    /// Which built-in overlay sample World > UI Lab shows (M8.1.4). Stored here
    /// because both samples share `Renderer.uiScene`; the UI Lab bridge maps it
    /// onto the renderer.
    enum UILabSampleSelection {
        case none, lab, localized
    }

    var uiLabSampleSelection: UILabSampleSelection = .none

    /// Builds the merged translation provider over the located install. Set by
    /// the AppDelegate; nil when game data is missing. The UI Lab bridge
    /// invokes it once, lazily, caching into `installLocalizedLabels`.
    var localizedLabelsLoader: (() -> LocalizedLabels)?
    /// Cache written only by the UI Lab bridge (`resolveInstallLabels`).
    var installLocalizedLabels: LocalizedLabels?
    var installLocalizedLabelsResolved = false

    override func loadView() {
        let gameView = GameMetalView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        gameView.input = cameraInput
        gameView.menuMode = menuMode
        view = gameView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = view as? MTKView else { return }

        if let startupErrorMessage {
            show(message: startupErrorMessage)
            return
        }

        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            show(message: "OpenSky requires a GPU with Metal 4 support.")
            return
        }
        mtkView.device = device

        // Async launch: no scene is built here. A provider (game data) starts
        // the renderer on an empty scene and streams cells in around the
        // camera; no provider (missing data / setup throw) falls back to the
        // synthetic DemoScene so the window is never blank forever.
        let provider = cellProviderFactory?(device)

        do {
            let newRenderer = try Renderer(
                view: mtkView,
                scene: provider != nil ? RenderScene(instances: []) : nil,
                camera: nil,
                input: cameraInput
            )
            // Persisted World > Environment > Sun shadows choice; invalid stored
            // value falls back to .high inside ShadowQualitySettings.load().
            newRenderer.shadowQuality = ShadowQualitySettings.load()
            // Persisted World > Environment > Time of day; invalid stored value
            // falls back to 13:00 inside TimeOfDaySettings.load().
            newRenderer.timeOfDay = TimeOfDaySettings.load()
            // Exterior weather runtime (M7.2.2); nil provider / no weather data
            // leaves the renderer on its procedural sky, exactly as before.
            newRenderer.weather = (provider as? WeatherProviding)?.weatherSystem
            newRenderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
            mtkView.delegate = newRenderer
            renderer = newRenderer
            // Menu mode drives the renderer's world-sim pause and clears held
            // world input on entry so no key sticks while the menu owns input.
            menuMode.onModeChange = { [weak newRenderer, weak cameraInput] paused in
                newRenderer?.worldSimPaused = paused
                if paused {
                    cameraInput?.releaseAll()
                }
            }
            if let provider {
                startStreaming(provider: provider, renderer: newRenderer)
            }
        } catch {
            show(message: "Renderer setup failed: \(error)")
        }
    }

    /// Wires a streamer over the provider: builds run off-main on a serial
    /// runner, the recomposed scene swaps in via `Renderer.setScene`, and the
    /// renderer's per-frame hook drives the streamer with the live camera
    /// position. Weak captures both ways -> no retain cycle (this controller
    /// owns both renderer + streamer).
    private func startStreaming(provider: any CellSceneProvider, renderer: Renderer) {
        let runner = SerialCellBuildRunner(provider: provider)
        let controller = CellStreamer(
            center: CellCoordinate(x: FirstRenderCell.gridX, y: FirstRenderCell.gridY),
            runner: runner,
            sink: { [weak renderer] scene, camera in
                do {
                    try renderer?.setScene(scene, camera: camera)
                } catch {
                    Self.logger.error(
                        "[ERROR] scene swap failed: \(String(describing: error), privacy: .public)"
                    )
                }
            }
        )
        renderer.onFrame = { [weak controller, weak cameraInput] position in
            controller?.update(
                cameraPosition: position,
                activate: cameraInput?.consumeActivation() ?? false
            )
        }
        // Live XCLR region feed (M7.2.3): the streamer pushes the center cell's
        // REGN set into the weather runtime so region-weighted selection runs
        // live. Same main thread as the draw loop -> WeatherSystem stays
        // single-thread-owned.
        controller.onCenterRegionsChanged = { [weak renderer] regions in
            renderer?.weather?.setRegions(regions)
        }
        renderer.terrainSampler = { [weak controller] position in
            controller?.sampleTerrain(at: position)
        }
        renderer.collisionQuery = { [weak controller] bounds in
            controller?.collisionCandidates(overlapping: bounds) ?? []
        }
        streamer = controller
    }

    /// Saves the live World camera + current streamed scene, excluding app
    /// chrome. Runs on main, same as draw(in:), so renderer state cannot race.
    func writeScreenshot(to url: URL) throws {
        guard let renderer, let view = view as? MTKView else {
            throw ScreenshotError.rendererNotReady
        }
        let width = Int(view.drawableSize.width.rounded())
        let height = Int(view.drawableSize.height.rounded())
        guard width > 0, height > 0 else {
            throw ScreenshotError.rendererNotReady
        }
        let texture = try renderer.renderOffscreen(width: width, height: height)
        try FrameScreenshot.write(texture: texture, to: url)
    }

    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "CellStream"
    )

    private func show(message: String) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.alignment = .center
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }
}

/// Renderer bridge for the World > Environment panel. Reads/writes the live
/// renderer's shadow state on the main thread (same context as draw(in:)) and
/// persists the quality choice. A nil renderer (Metal 4 unavailable) degrades to
/// the stored/default quality and empty stats so the panel never crashes.
extension GameViewController: ShadowControlProviding {
    var shadowQuality: ShadowQuality {
        get { renderer?.shadowQuality ?? ShadowQualitySettings.load() }
        set {
            renderer?.shadowQuality = newValue
            ShadowQualitySettings.store(newValue)
        }
    }

    var shadowDrawStats: ShadowDrawStats {
        renderer?.lastShadowDrawStats ?? ShadowDrawStats()
    }

    var shadowUpdateMS: Double {
        renderer?.lastShadowUpdateMS ?? 0
    }

    var shadowsActive: Bool {
        renderer?.shadowRenders ?? false
    }

    func refocusGameView() {
        view.window?.makeFirstResponder(view)
    }
}

extension GameViewController: TerrainLODControlProviding {
    var terrainLODConfigurationSnapshot: TerrainLODConfigurationSnapshot {
        terrainLODConfigurationStore.snapshot()
    }

    func applyTerrainLODConfiguration(_ configuration: TerrainLODConfiguration) -> Bool {
        guard configuration.isValid else { return false }
        TerrainLODSettings.store(configuration)
        terrainLODConfigurationStore.replace(with: TerrainLODConfigurationSnapshot(
            configuration: configuration,
            source: "OpenSky sidebar override"
        ))
        streamer?.invalidateDistantLOD()
        return true
    }

    func resetTerrainLODConfiguration() {
        TerrainLODSettings.clearOverride()
        let root = try? GameDataLocator.locate()
        terrainLODConfigurationStore.replace(with: TerrainLODSettings.load(root: root))
        streamer?.invalidateDistantLOD()
    }
}

/// Weather bridge for the World > Environment panel (M7.2.2). Reads/forces the
/// live renderer's weather runtime on the main thread. A nil renderer or no
/// weather data degrades to an empty list + calm readout.
extension GameViewController: WeatherControlProviding {
    var weatherEnabled: Bool {
        get { renderer?.weatherEnabled ?? true }
        set { renderer?.weatherEnabled = newValue }
    }

    var selectableWeatherNames: [String] {
        (renderer?.weather?.store.selectableWeathers() ?? [])
            .compactMap(\.editorID)
    }

    func forceWeather(named name: String?) {
        guard let weather = renderer?.weather else { return }
        guard let name else {
            weather.forceWeather(nil, transition: .timed)
            return
        }
        let match = weather.store.selectableWeathers().first { $0.editorID == name }
        weather.forceWeather(match?.formID, transition: .timed)
    }

    func forceWeather(_ preset: WeatherPreset) {
        guard
            let weather = renderer?.weather,
            let match = weather.store.weather(for: preset)
        else { return }
        weather.forceWeather(match.formID, transition: .timed)
    }

    var currentWeatherName: String? {
        renderer?.weather?.currentWeatherEditorID
    }

    var weatherTransitionFraction: Float {
        renderer?.weather?.transitionFraction ?? 1
    }

    var weatherTransitionsPaused: Bool {
        get { renderer?.weather?.transitionsPaused ?? false }
        set { renderer?.weather?.transitionsPaused = newValue }
    }

    var windState: WindState {
        renderer?.currentWind ?? .calm
    }

    var timeOfDay: Float {
        get { renderer?.timeOfDay ?? TimeOfDaySettings.load() }
        set {
            renderer?.timeOfDay = newValue
            TimeOfDaySettings.store(newValue)
        }
    }
}

extension GameViewController: AnimationControlProviding {
    var actorAnimationsEnabled: Bool {
        get { renderer?.actorAnimationsEnabled ?? true }
        set { renderer?.actorAnimationsEnabled = newValue }
    }

    var animationSnapshot: AnimationControlSnapshot {
        AnimationControlSnapshot(
            playbackCount: renderer?.scene.animations.count ?? 0,
            updatedBoneCount: renderer?.lastAnimationUpdatedBoneCount ?? 0,
            updateMS: renderer?.lastAnimationUpdateMS ?? 0
        )
    }
}

extension GameViewController: ParticleControlProviding {
    var particlesEnabled: Bool {
        get { renderer?.particlesEnabled ?? true }
        set { renderer?.particlesEnabled = newValue }
    }

    var particlesFrozen: Bool {
        get { renderer?.particlesFrozen ?? false }
        set { renderer?.particlesFrozen = newValue }
    }

    var particleEmissionScale: Float {
        get { renderer?.particleEmissionScale ?? 1 }
        set { renderer?.particleEmissionScale = simd_clamp(newValue, 0, 2) }
    }

    var particleSnapshot: ParticleControlSnapshot {
        let playbacks = renderer?.scene.particles ?? []
        return ParticleControlSnapshot(
            systemCount: playbacks.count,
            emitterCount: playbacks.reduce(0) { $0 + $1.emitterCount },
            liveCount: playbacks.reduce(0) { $0 + $1.liveCount }
        )
    }
}

extension GameViewController: PrecipitationControlProviding {
    var precipitationEnabled: Bool {
        get { renderer?.precipitationEnabled ?? true }
        set { renderer?.precipitationEnabled = newValue }
    }

    var precipitationSnapshot: PrecipitationRuntimeSnapshot {
        renderer?.precipitation.snapshot ?? PrecipitationRuntimeSnapshot(
            state: .none,
            roofOccluded: false,
            rainLiveCount: 0,
            snowLiveCount: 0
        )
    }
}

extension GameViewController: GrassControlProviding {
    var grassEnabled: Bool {
        get { renderer?.grassEnabled ?? true }
        set { renderer?.grassEnabled = newValue }
    }

    var grassDensityScale: Float {
        get { renderer?.grassDensityScale ?? 1 }
        set { renderer?.grassDensityScale = simd_clamp(newValue, 0, 1) }
    }

    var grassDrawDistance: Float {
        get { renderer?.grassDrawDistance ?? GrassRenderPolicy.defaultDrawDistance }
        set {
            renderer?.grassDrawDistance = simd_clamp(
                newValue,
                GrassRenderPolicy.minimumDrawDistance,
                GrassRenderPolicy.maximumDrawDistance
            )
        }
    }

    var grassWindScale: Float {
        get { renderer?.grassWindScale ?? 1 }
        set {
            renderer?.grassWindScale = simd_clamp(
                newValue, 0, GrassRenderPolicy.maximumWindScale
            )
        }
    }

    var grassSnapshot: GrassControlSnapshot {
        let stats = renderer?.lastGrassDrawStats ?? GrassDrawStats()
        return GrassControlSnapshot(
            sceneInstances: stats.sceneInstances,
            drawnInstances: stats.drawnInstances,
            drawCalls: stats.drawCalls,
            distanceCulledInstances: stats.distanceCulledInstances,
            densityCulledInstances: stats.densityCulledInstances,
            frustumCulledInstances: stats.frustumCulledInstances,
            budgetDroppedInstances: stats.budgetDroppedInstances
        )
    }
}
