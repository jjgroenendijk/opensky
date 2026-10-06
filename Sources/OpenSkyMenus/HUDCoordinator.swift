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
    public private(set) var sync = HUDSyncState()
    public private(set) var settings = HUDSettings()

    private let movies: SWFMovieSource
    /// Bumped by each start and suspend, so only the newest start shows the HUD.
    private var startRequest = 0
    private weak var world: SWFLayerWorld?

    public init(movies: SWFMovieSource) {
        self.movies = movies
    }

    public func attach(world: SWFLayerWorld) {
        self.world = world
    }

    private var renderer: Renderer? {
        world?.renderer
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
            renderer.swfEnabled = settings.layerEnabled
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
        guard isLoaded, let renderer else { return }
        let camera = renderer.freeFlyCamera
        let heading = HUDCore.headingDegrees(camera.yaw)
        let update = HUDCore.frameUpdate(
            sync: sync,
            hasTarget: interactionTarget != nil,
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

    /// Lines the movie showed, newest last, for the panel readout.
    public private(set) var shownNotifications: [String] = []

    public func showNotification(_ text: String) {
        shownNotifications = Array((shownNotifications + [text]).suffix(5))
        callMovie { HUDMovieBridge.showNotification(text, runtime: $0) }
    }

    public private(set) var shownSubtitle: String?

    public func setHelpMessage(_ text: String?) {
        callMovie { HUDMovieBridge.setHelpMessage(text, runtime: $0) }
    }

    private func callMovie(_ body: (SWFMovieRuntime) -> Void) {
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
        sync.markersNeedUpdate = oldReference != target?.interaction.reference
    }

    public var effectivePrompt: String? {
        HUDCore.effectivePrompt(settings, target: interactionTarget)
    }

    public func effectiveMarkers(cameraPosition: SIMD3<Float>) -> [HUDCompassMarker] {
        HUDCore.effectiveMarkers(
            settings, target: interactionTarget, cameraPosition: cameraPosition
        )
    }

    public var controlSnapshot: HUDControlSnapshot {
        let target = interactionTarget
        let cameraPosition = renderer?.freeFlyCamera.position ?? .zero
        return HUDControlSnapshot(
            isLoaded: isLoaded,
            loadError: loadError,
            targetReference: target?.interaction.reference,
            targetBase: target?.interaction.base,
            targetName: target?.interaction.name,
            targetAction: target?.interaction.actionLabel,
            targetDistance: target?.distance,
            targetPosition: target?.interaction.position,
            hitPosition: target?.hitPosition,
            prompt: effectivePrompt,
            markerHeadings: effectiveMarkers(cameraPosition: cameraPosition)
                .map(\.headingDegrees),
            cameraHeading: renderer.map { HUDCore.headingDegrees($0.freeFlyCamera.yaw) },
            scale: settings.scale,
            drawStats: renderer?.lastSWFDrawStats ?? SWFDrawStats()
        )
    }

    /// Applies one panel change. The layer toggle and the scale reach the
    /// renderer only; every other change republishes the movie state.
    public func update(_ change: (inout HUDSettings) -> Void) {
        let old = settings
        change(&settings)
        settings.scale = HUDCore.clampedScale(settings.scale)
        guard isLoaded, let renderer else { return }
        renderer.swfEnabled = settings.layerEnabled
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
        let camera = renderer.freeFlyCamera
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
            HUDMovieBridge.setMetersEnabled(settings.metersEnabled, runtime: runtime)
            HUDMovieBridge.setCompassHeading(
                heading, visible: settings.compassEnabled, runtime: runtime
            )
            HUDMovieBridge.setAuthoredPlaceholderTextEnabled(
                settings.placeholderTextEnabled, runtime: runtime
            )
        }
        markSynced(cameraPosition: camera.position, heading: heading)
    }

    private func markSynced(cameraPosition: SIMD3<Float>, heading: Float) {
        sync.promptNeedsUpdate = false
        sync.markersNeedUpdate = false
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
