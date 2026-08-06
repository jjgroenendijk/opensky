// Vanilla gameplay HUD (M8.4.2): loads `Interface\hudmenu.swf`, starts its AS2
// runtime, publishes interaction prompts, and drives meters plus compass state.
// AppKit stays in this controller satellite; the typed movie contract is in
// UI/HUDMovieBridge.swift and builds into both app and CLI targets.

import AppKit
import OSLog
import simd

struct HUDRuntimeState {
    var isLoaded = false
    var loadError: String?
    var interactionTarget: InteractionTarget?
    var layerEnabled = true
    var crosshairEnabled = true
    var metersEnabled = true
    var compassEnabled = true
    var markersEnabled = true
    var promptEnabled = true
    var placeholderTextEnabled = false
    var scale: Float = 1
    var promptNeedsUpdate = false
    var markersNeedUpdate = false
    var lastCameraPosition: SIMD3<Float>?
    var lastHeadingDegrees: Float?
}

extension GameViewController {
    func startHUD(renderer: Renderer) {
        guard let loader = resolveSWFLoader() else {
            failHUD(HUDMovieError.movieLoaderUnavailable, renderer: renderer)
            return
        }
        do {
            let scene = try loader.load(path: HUDMovieBridge.moviePath)
            try renderer.setSWFMovie(scene)
            renderer.swfEnabled = hud.layerEnabled
            renderer.swfScale = hud.scale
            guard let runtime = try renderer.startSWFRuntime() else {
                return
            }
            try HUDMovieBridge.validate(runtime: runtime)
            let heading = Self.hudHeadingDegrees(renderer.freeFlyCamera.yaw)
            try renderer.updateSWFRuntime { runtime in
                HUDMovieBridge.initialize(
                    runtime: runtime,
                    headingDegrees: heading,
                    markers: effectiveHUDMarkers(cameraPosition: renderer.freeFlyCamera.position),
                    activationPrompt: effectiveHUDPrompt
                )
                HUDMovieBridge.setCrosshairEnabled(
                    hud.crosshairEnabled,
                    runtime: runtime
                )
                HUDMovieBridge.setMetersEnabled(hud.metersEnabled, runtime: runtime)
                HUDMovieBridge.setCompassHeading(
                    heading,
                    visible: hud.compassEnabled,
                    runtime: runtime
                )
                HUDMovieBridge.setAuthoredPlaceholderTextEnabled(
                    hud.placeholderTextEnabled,
                    runtime: runtime
                )
            }
            hud.isLoaded = true
            hud.loadError = nil
            hud.promptNeedsUpdate = false
            hud.markersNeedUpdate = false
            hud.lastCameraPosition = renderer.freeFlyCamera.position
            hud.lastHeadingDegrees = heading
        } catch {
            failHUD(error, renderer: renderer)
        }
    }

    func updateHUDFrame(renderer: Renderer) {
        guard hud.isLoaded else {
            return
        }
        let camera = renderer.freeFlyCamera
        let heading = Self.hudHeadingDegrees(camera.yaw)
        let headingNeedsUpdate = heading != hud.lastHeadingDegrees
        let markersNeedUpdate = hud.markersNeedUpdate
            || (hud.interactionTarget != nil && camera.position != hud.lastCameraPosition)
        guard hud.promptNeedsUpdate || headingNeedsUpdate || markersNeedUpdate else {
            return
        }
        do {
            try renderer.updateSWFRuntime { runtime in
                if hud.promptNeedsUpdate {
                    HUDMovieBridge.setActivationPrompt(
                        effectiveHUDPrompt,
                        runtime: runtime
                    )
                }
                if markersNeedUpdate {
                    HUDMovieBridge.setCompassMarkers(
                        effectiveHUDMarkers(cameraPosition: camera.position),
                        runtime: runtime
                    )
                }
                if headingNeedsUpdate {
                    HUDMovieBridge.setCompassHeading(
                        heading,
                        visible: hud.compassEnabled,
                        runtime: runtime
                    )
                }
            }
            hud.promptNeedsUpdate = false
            hud.markersNeedUpdate = false
            hud.lastCameraPosition = camera.position
            hud.lastHeadingDegrees = heading
        } catch {
            failHUD(error, renderer: renderer)
        }
    }

    func updateHUDTarget(_ target: InteractionTarget?) {
        let oldPrompt = effectiveHUDPrompt
        let oldReference = hud.interactionTarget?.interaction.reference
        hud.interactionTarget = target
        hud.promptNeedsUpdate = oldPrompt != effectiveHUDPrompt
        hud.markersNeedUpdate = oldReference != target?.interaction.reference
    }

    static func hudPrompt(for target: InteractionTarget?) -> String? {
        guard let interaction = target?.interaction else {
            return nil
        }
        return "\(interaction.actionLabel) \(interaction.name)"
    }

    static func hudHeadingDegrees(_ yawRadians: Float) -> Float {
        HUDMovieBridge.normalizedDegrees(yawRadians * 180 / .pi)
    }

    static func hudMarkers(
        for target: InteractionTarget?,
        cameraPosition: SIMD3<Float>
    ) -> [HUDCompassMarker] {
        guard let target else {
            return []
        }
        let offset = target.interaction.position - cameraPosition
        guard simd_length_squared(SIMD2<Float>(offset.x, offset.y)) > 0.0001 else {
            return []
        }
        let heading = hudHeadingDegrees(atan2(offset.y, offset.x))
        return [HUDCompassMarker(headingDegrees: heading, kind: .location)]
    }

    private var effectiveHUDPrompt: String? {
        guard hud.promptEnabled else { return nil }
        return Self.hudPrompt(for: hud.interactionTarget)
    }

    private func effectiveHUDMarkers(
        cameraPosition: SIMD3<Float>
    ) -> [HUDCompassMarker] {
        guard hud.markersEnabled else { return [] }
        return Self.hudMarkers(
            for: hud.interactionTarget,
            cameraPosition: cameraPosition
        )
    }

    private func applyHUDPresentation() {
        guard hud.isLoaded, let renderer else { return }
        let heading = Self.hudHeadingDegrees(renderer.freeFlyCamera.yaw)
        do {
            try renderer.updateSWFRuntime { runtime in
                HUDMovieBridge.setCrosshairEnabled(
                    hud.crosshairEnabled,
                    runtime: runtime
                )
                HUDMovieBridge.setMetersEnabled(hud.metersEnabled, runtime: runtime)
                HUDMovieBridge.setCompassHeading(
                    heading,
                    visible: hud.compassEnabled,
                    runtime: runtime
                )
                HUDMovieBridge.setCompassMarkers(
                    effectiveHUDMarkers(cameraPosition: renderer.freeFlyCamera.position),
                    runtime: runtime
                )
                HUDMovieBridge.setActivationPrompt(effectiveHUDPrompt, runtime: runtime)
                HUDMovieBridge.setAuthoredPlaceholderTextEnabled(
                    hud.placeholderTextEnabled,
                    runtime: runtime
                )
            }
            hud.promptNeedsUpdate = false
            hud.markersNeedUpdate = false
            hud.lastCameraPosition = renderer.freeFlyCamera.position
            hud.lastHeadingDegrees = heading
        } catch {
            failHUD(error, renderer: renderer)
        }
    }

    private func failHUD(_ error: Error, renderer: Renderer) {
        try? renderer.setSWFMovie(nil)
        hud.isLoaded = false
        hud.loadError = String(describing: error)
        Self.hudLogger.error(
            "[ERROR] HUD disabled: \(String(describing: error), privacy: .public)"
        )
    }

    func wireHUDFrameUpdates(renderer: Renderer) {
        renderer.onFrame.add { [weak self, weak renderer] _ in
            guard let renderer else { return }
            self?.updateHUDFrame(renderer: renderer)
        }
    }

    private static let hudLogger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "HUD"
    )
}

extension GameViewController: HUDControlProviding {
    var hudLayerEnabled: Bool {
        get { hud.layerEnabled }
        set {
            hud.layerEnabled = newValue
            if hud.isLoaded {
                renderer?.swfEnabled = newValue
            }
        }
    }

    var hudCrosshairEnabled: Bool {
        get { hud.crosshairEnabled }
        set {
            hud.crosshairEnabled = newValue
            applyHUDPresentation()
        }
    }

    var hudCompassEnabled: Bool {
        get { hud.compassEnabled }
        set {
            hud.compassEnabled = newValue
            applyHUDPresentation()
        }
    }

    var hudMetersEnabled: Bool {
        get { hud.metersEnabled }
        set {
            hud.metersEnabled = newValue
            applyHUDPresentation()
        }
    }

    var hudMarkersEnabled: Bool {
        get { hud.markersEnabled }
        set {
            hud.markersEnabled = newValue
            applyHUDPresentation()
        }
    }

    var hudPromptEnabled: Bool {
        get { hud.promptEnabled }
        set {
            hud.promptEnabled = newValue
            applyHUDPresentation()
        }
    }

    var hudPlaceholderTextEnabled: Bool {
        get { hud.placeholderTextEnabled }
        set {
            hud.placeholderTextEnabled = newValue
            applyHUDPresentation()
        }
    }

    var hudScale: Float {
        get { hud.scale }
        set {
            let finite = newValue.isFinite ? newValue : 1
            hud.scale = max(0.5, min(2, finite))
            if hud.isLoaded {
                renderer?.swfScale = hud.scale
            }
        }
    }

    var hudControlSnapshot: HUDControlSnapshot {
        let target = hud.interactionTarget
        let cameraPosition = renderer?.freeFlyCamera.position ?? .zero
        return HUDControlSnapshot(
            isLoaded: hud.isLoaded,
            loadError: hud.loadError,
            targetReference: target?.interaction.reference,
            targetBase: target?.interaction.base,
            targetName: target?.interaction.name,
            targetAction: target?.interaction.actionLabel,
            targetDistance: target?.distance,
            targetPosition: target?.interaction.position,
            hitPosition: target?.hitPosition,
            prompt: effectiveHUDPrompt,
            markerHeadings: effectiveHUDMarkers(cameraPosition: cameraPosition)
                .map(\.headingDegrees),
            cameraHeading: renderer.map { Self.hudHeadingDegrees($0.freeFlyCamera.yaw) },
            scale: hudScale,
            drawStats: renderer?.lastSWFDrawStats ?? SWFDrawStats()
        )
    }
}
