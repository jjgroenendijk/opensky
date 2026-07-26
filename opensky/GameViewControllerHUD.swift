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
            guard let runtime = try renderer.startSWFRuntime() else {
                return
            }
            try HUDMovieBridge.validate(runtime: runtime)
            let heading = Self.hudHeadingDegrees(renderer.freeFlyCamera.yaw)
            try renderer.updateSWFRuntime { runtime in
                HUDMovieBridge.initialize(
                    runtime: runtime,
                    headingDegrees: heading,
                    markers: Self.hudMarkers(
                        for: hud.interactionTarget,
                        cameraPosition: renderer.freeFlyCamera.position
                    ),
                    activationPrompt: Self.hudPrompt(for: hud.interactionTarget)
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
                        Self.hudPrompt(for: hud.interactionTarget),
                        runtime: runtime
                    )
                }
                if markersNeedUpdate {
                    HUDMovieBridge.setCompassMarkers(
                        Self.hudMarkers(
                            for: hud.interactionTarget,
                            cameraPosition: camera.position
                        ),
                        runtime: runtime
                    )
                }
                if headingNeedsUpdate {
                    HUDMovieBridge.setCompassHeading(heading, runtime: runtime)
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
        let oldPrompt = Self.hudPrompt(for: hud.interactionTarget)
        let oldReference = hud.interactionTarget?.interaction.reference
        hud.interactionTarget = target
        hud.promptNeedsUpdate = oldPrompt != Self.hudPrompt(for: target)
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

    private func failHUD(_ error: Error, renderer: Renderer) {
        try? renderer.setSWFMovie(nil)
        hud.isLoaded = false
        hud.loadError = String(describing: error)
        Self.hudLogger.error(
            "[ERROR] HUD disabled: \(String(describing: error), privacy: .public)"
        )
    }

    func wireHUDFrameUpdates(renderer: Renderer) {
        renderer.onFrame = { [weak self, weak renderer] _ in
            guard let renderer else { return }
            self?.updateHUDFrame(renderer: renderer)
        }
    }

    private static let hudLogger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "HUD"
    )
}
