// Pure rules of the gameplay HUD: the prompt text, the compass values, and
// which parts of the movie a frame must refresh.

import OpenSkyWorldInterface
import simd

nonisolated public struct HUDSettings: Equatable, Sendable {
    public var layerEnabled = true
    public var crosshairEnabled = true
    public var metersEnabled = true
    public var compassEnabled = true
    public var markersEnabled = true
    public var promptEnabled = true
    public var placeholderTextEnabled = false
    public var scale: Float = 1

    public init() {}
}

/// The values last sent to the movie, so a frame sends only what changed.
nonisolated public struct HUDSyncState: Equatable, Sendable {
    public var promptNeedsUpdate = false
    public var markersNeedUpdate = false
    public var lastCameraPosition: SIMD3<Float>?
    public var lastHeadingDegrees: Float?

    public init() {}
}

nonisolated public struct HUDFrameUpdate: Equatable, Sendable {
    public var prompt: Bool
    public var markers: Bool
    public var heading: Bool

    public var isEmpty: Bool {
        !prompt && !markers && !heading
    }
}

nonisolated public enum HUDCore {
    public static let scaleRange: ClosedRange<Float> = 0.5 ... 2

    public static func prompt(for target: InteractionTarget?) -> String? {
        guard let interaction = target?.interaction else {
            return nil
        }
        return "\(interaction.actionLabel) \(interaction.name)"
    }

    public static func headingDegrees(_ yawRadians: Float) -> Float {
        HUDMovieBridge.normalizedDegrees(yawRadians * 180 / .pi)
    }

    public static func markers(
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
        let heading = headingDegrees(atan2(offset.y, offset.x))
        return [HUDCompassMarker(headingDegrees: heading, kind: .location)]
    }

    public static func effectivePrompt(
        _ settings: HUDSettings,
        target: InteractionTarget?
    ) -> String? {
        settings.promptEnabled ? prompt(for: target) : nil
    }

    public static func effectiveMarkers(
        _ settings: HUDSettings,
        target: InteractionTarget?,
        cameraPosition: SIMD3<Float>
    ) -> [HUDCompassMarker] {
        settings.markersEnabled ? markers(for: target, cameraPosition: cameraPosition) : []
    }

    /// A marker follows the camera, so it moves whenever the camera does while a
    /// target is set.
    public static func frameUpdate(
        sync: HUDSyncState,
        hasTarget: Bool,
        cameraPosition: SIMD3<Float>,
        heading: Float
    ) -> HUDFrameUpdate {
        HUDFrameUpdate(
            prompt: sync.promptNeedsUpdate,
            markers: sync.markersNeedUpdate
                || (hasTarget && cameraPosition != sync.lastCameraPosition),
            heading: heading != sync.lastHeadingDegrees
        )
    }

    /// A non-finite scale falls back to 1.
    public static func clampedScale(_ scale: Float) -> Float {
        let finite = scale.isFinite ? scale : 1
        return min(max(finite, scaleRange.lowerBound), scaleRange.upperBound)
    }
}
