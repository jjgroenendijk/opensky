// The vanilla gameplay HUD: loads `Interface\hudmenu.swf`, starts its AS2
// runtime, and keeps the prompt, meters, and compass in step with the camera.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWorldInterface
import simd

public final class HUDCoordinator {
    public private(set) var isLoaded = false
    public private(set) var loadError: String?
    public private(set) var interactionTarget: InteractionTarget?
    /// Where the tracked quests' targets stand, for the compass.
    public private(set) var questTargets: [SIMD3<Float>] = []
    /// Kept apart from the target's change, which `updateTarget` sets every frame.
    private var questTargetsChanged = false
    public private(set) var sync = HUDSyncState()
    public private(set) var settings = HUDSettings()
    /// A loading screen hides the HUD, as `LoadingMenu` does in the game.
    public private(set) var isCovered = false

    private let movies: SWFMovieSource
    /// Bumped by each start and suspend, so only the newest start shows the HUD.
    private var startRequest = 0
    private weak let world: SWFLayerWorld?

    public init(movies: SWFMovieSource, world: SWFLayerWorld? = nil) {
        self.movies = movies
        self.world = world
    }

    var renderer: Renderer? {
        world?.renderer
    }

    /// Hides the HUD while a loading screen is up, and shows it again after.
    /// The loading movie draws on the overlay layer, so only the main movie hides.
    public func setCovered(_ covered: Bool) {
        isCovered = covered
        renderer?.swfMainMovieHidden = covered
    }

    /// `Game.SetHudCartMode` sets `cart`; the frame sets the rest from the player.
    public private(set) var modeInputs = HUDModeInputs()
    /// The stack the movie holds, bottom first.
    public private(set) var shownModes: [HUDMode] = []

    public var isCartMode: Bool {
        modeInputs.cart
    }

    public func setCartMode(_ enabled: Bool) {
        var inputs = modeInputs
        inputs.cart = enabled
        updateModes(inputs)
    }

    /// Keeps the script's cart mode; every other input comes from `inputs`.
    public func updatePlayerModes(_ inputs: HUDModeInputs) {
        var inputs = inputs
        inputs.cart = modeInputs.cart
        updateModes(inputs)
    }

    private func updateModes(_ inputs: HUDModeInputs) {
        modeInputs = inputs
        let modes = HUDModeRules.modes(inputs)
        guard isLoaded, modes != shownModes else { return }
        callMovie { applyModes(modes, runtime: $0) }
    }

    /// Pops every shown mode, then pushes the new stack, so the movie's own
    /// stack always matches `shownModes`.
    private func applyModes(_ modes: [HUDMode], runtime: SWFMovieRuntime) {
        for mode in shownModes.reversed() {
            HUDMovieBridge.showElements(mode, false, runtime: runtime)
        }
        for mode in modes {
            HUDMovieBridge.showElements(mode, true, runtime: runtime)
        }
        shownModes = modes
        applyClipSwitches(runtime: runtime)
    }

    /// OpenSky's switches write the same `_visible` the movie's modes write, so each
    /// one is applied again after a mode change, and never shows what the top mode hides.
    private func applyClipSwitches(runtime: SWFMovieRuntime) {
        let meters = Set([HUDModeClip.health, .magicka, .stamina].filter {
            settings.metersEnabled && shows($0)
        })
        HUDMovieBridge.setMetersVisible(meters, runtime: runtime)
        HUDMovieBridge.setAuthoredPlaceholderTextEnabled(
            settings.placeholderTextEnabled && shows(.itemInfo), runtime: runtime
        )
        if let shownSubtitle {
            HUDMovieBridge.setSubtitleText(shownSubtitle, runtime: runtime)
        }
    }

    public func shows(_ clip: HUDModeClip) -> Bool {
        HUDModeRules.shows(clip, under: shownModes)
    }

    private var layerVisible: Bool {
        settings.layerEnabled
    }

    /// Takes the HUD off the SWF layer, so a menu that owns the layer next can
    /// never be changed by a HUD update.
    public func suspend() {
        isLoaded = false
        startRequest += 1
    }

    /// The HUD shows once its movie is decoded. A menu that takes the layer first
    /// cancels it, through `suspend()`.
    public func start() {
        guard let renderer else { return }
        guard movies.isAvailable else {
            fail(HUDMovieError.movieLoaderUnavailable, renderer: renderer)
            return
        }
        startRequest += 1
        let request = startRequest
        movies.request(HUDMovieBridge.moviePath, while: { [weak self] in
            self?.startRequest == request
        }, then: { [weak self] result in
            self?.show(result)
        })
    }

    private func show(_ result: Result<SWFMovieScene, AssetLoadFailure>) {
        guard let renderer else { return }
        do {
            let scene = try result.get()
            try renderer.setSWFMovie(scene)
            renderer.swfEnabled = layerVisible
            renderer.swfScale = settings.scale
            guard let runtime = try renderer.startSWFRuntime() else {
                return
            }
            try HUDMovieBridge.validate(runtime: runtime)
            isLoaded = true
            loadError = nil
            try publish(renderer: renderer, initialize: true)
        } catch {
            fail(error, renderer: renderer)
        }
    }

    public func updateFrame() {
        guard isLoaded, let renderer, let camera = world?.viewCamera else { return }
        let heading = HUDCore.headingDegrees(camera.yaw)
        let update = HUDCore.frameUpdate(
            sync: sync,
            hasTarget: interactionTarget != nil || !questTargets.isEmpty,
            cameraPosition: camera.position,
            heading: heading
        )
        guard !update.isEmpty else { return }
        do {
            try renderer.updateSWFRuntime { runtime in
                if update.prompt {
                    HUDMovieBridge.setActivationPrompt(effectivePrompt, runtime: runtime)
                }
                if update.markers {
                    HUDMovieBridge.setCompassMarkers(
                        effectiveMarkers(cameraPosition: camera.position),
                        runtime: runtime
                    )
                }
                if update.heading {
                    HUDMovieBridge.setCompassHeading(
                        heading, visible: settings.compassEnabled, runtime: runtime
                    )
                }
            }
            markSynced(cameraPosition: camera.position, heading: heading)
        } catch {
            fail(error, renderer: renderer)
        }
    }

    /// Lines the movie showed, newest last, for the readout.
    public private(set) var shownNotifications: [String] = []

    public func showNotification(_ text: String) {
        shownNotifications = Array((shownNotifications + [text]).suffix(5))
        callMovie { HUDMovieBridge.showNotification(text, runtime: $0) }
    }

    /// Big notices the movie showed, newest last, for the readout.
    public internal(set) var shownBigNotices: [HUDBigNotice] = []

    public private(set) var shownSubtitle: String?

    public func setHelpMessage(_ text: String?) {
        callMovie { HUDMovieBridge.setHelpMessage(text, runtime: $0) }
    }

    func callMovie(_ body: (SWFMovieRuntime) -> Void) {
        guard isLoaded, let renderer else { return }
        do {
            try renderer.updateSWFRuntime(body)
        } catch {
            fail(error, renderer: renderer)
        }
    }

    public func updateTarget(_ target: InteractionTarget?) {
        let oldPrompt = effectivePrompt
        let oldReference = interactionTarget?.interaction.reference
        interactionTarget = target
        sync.promptNeedsUpdate = oldPrompt != effectivePrompt
        sync.markersNeedUpdate = questTargetsChanged
            || oldReference != target?.interaction.reference
    }

    public func updateQuestTargets(_ positions: [SIMD3<Float>]) {
        guard positions != questTargets else { return }
        questTargets = positions
        questTargetsChanged = true
        sync.markersNeedUpdate = true
    }

    public var effectivePrompt: String? {
        HUDCore.effectivePrompt(settings, target: interactionTarget)
    }

    public func effectiveMarkers(cameraPosition: SIMD3<Float>) -> [HUDCompassMarker] {
        HUDCore.effectiveMarkers(
            settings, target: interactionTarget, questTargets: questTargets,
            cameraPosition: cameraPosition
        )
    }

    public var controlSnapshot: HUDControlSnapshot {
        HUDControlSnapshot(
            prompt: effectivePrompt,
            cameraHeading: world?.viewCamera.map { HUDCore.headingDegrees($0.yaw) },
            scale: settings.scale
        )
    }

    /// Applies one readout change. The layer toggle and the scale reach the
    /// renderer only; every other change republishes the movie state.
    public func update(_ change: (inout HUDSettings) -> Void) {
        let old = settings
        change(&settings)
        settings.scale = HUDCore.clampedScale(settings.scale)
        guard isLoaded, let renderer else { return }
        renderer.swfEnabled = layerVisible
        renderer.swfScale = settings.scale
        var presentation = settings
        presentation.layerEnabled = old.layerEnabled
        presentation.scale = old.scale
        guard presentation != old else { return }
        do {
            try publish(renderer: renderer, initialize: false)
        } catch {
            fail(error, renderer: renderer)
        }
    }

    /// `initialize` also fills the meters, so only a fresh movie asks for it.
    private func publish(renderer: Renderer, initialize: Bool) throws {
        let camera = world?.viewCamera ?? renderer.frameInput.view
        let heading = HUDCore.headingDegrees(camera.yaw)
        let markers = effectiveMarkers(cameraPosition: camera.position)
        try renderer.updateSWFRuntime { runtime in
            if initialize {
                HUDMovieBridge.initialize(
                    runtime: runtime,
                    headingDegrees: heading,
                    markers: markers,
                    activationPrompt: effectivePrompt
                )
            } else {
                HUDMovieBridge.setCompassMarkers(markers, runtime: runtime)
                HUDMovieBridge.setActivationPrompt(effectivePrompt, runtime: runtime)
            }
            HUDMovieBridge.setCrosshairEnabled(settings.crosshairEnabled, runtime: runtime)
            if initialize {
                shownModes = []
            }
            HUDMovieBridge.setCompassHeading(
                heading, visible: settings.compassEnabled, runtime: runtime
            )
            applyModes(HUDModeRules.modes(modeInputs), runtime: runtime)
        }
        markSynced(cameraPosition: camera.position, heading: heading)
    }

    private func markSynced(cameraPosition: SIMD3<Float>, heading: Float) {
        sync.promptNeedsUpdate = false
        sync.markersNeedUpdate = false
        questTargetsChanged = false
        sync.lastCameraPosition = cameraPosition
        sync.lastHeadingDegrees = heading
    }

    private func fail(_ error: Error, renderer: Renderer) {
        try? renderer.setSWFMovie(nil)
        isLoaded = false
        loadError = String(describing: error)
        Self.logger.error("[ERROR] HUD disabled: \(String(describing: error), privacy: .public)")
    }

    private static let logger = EngineLogger(subsystem: "nl.jjgroenendijk.opensky", category: "HUD")
}

extension HUDCoordinator: SubtitlePresenting {
    public func presentSubtitle(_ text: String?) {
        shownSubtitle = text
        callMovie { HUDMovieBridge.setSubtitleText(text, runtime: $0) }
    }
}
