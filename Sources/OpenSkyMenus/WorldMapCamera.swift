// The world map camera: a point above the worldspace that pans, zooms, and tilts
// inside the WRLD map limits (MNAM). Pure math; the renderer draws from its pose.
// See docs/engine/world-map.md.

import Foundation
import OpenSkyFormatsESM
import simd

nonisolated public struct WorldMapLimits: Equatable, Sendable {
    public static let cellSize: Float = 4096

    /// South-west and north-east corners in world units.
    public var minimum: SIMD2<Float>
    public var maximum: SIMD2<Float>
    public var minHeight: Float
    public var maxHeight: Float
    /// Degrees down from the horizon at the start.
    public var initialPitch: Float

    public init(
        minimum: SIMD2<Float>, maximum: SIMD2<Float>, minHeight: Float, maxHeight: Float,
        initialPitch: Float
    ) {
        self.minimum = simd_min(minimum, maximum)
        self.maximum = simd_max(minimum, maximum)
        self.minHeight = min(minHeight, maxHeight)
        self.maxHeight = max(minHeight, maxHeight)
        self.initialPitch = initialPitch
    }

    /// The usable area from the NW and SE cells. Missing camera values fall back
    /// to the Tamriel values, measured from Skyrim.esm (docs/engine/world-map.md).
    public init(map: WorldspaceMapData) {
        let northWest = SIMD2<Float>(Float(map.northWestCell.x), Float(map.northWestCell.y + 1))
        let southEast = SIMD2<Float>(Float(map.southEastCell.x + 1), Float(map.southEastCell.y))
        self.init(
            minimum: SIMD2(northWest.x, southEast.y) * Self.cellSize,
            maximum: SIMD2(southEast.x, northWest.y) * Self.cellSize,
            minHeight: map.cameraMinHeight ?? 50000, maxHeight: map.cameraMaxHeight ?? 80000,
            initialPitch: map.cameraInitialPitch ?? 50
        )
    }
}

nonisolated public struct WorldMapCamera: Equatable, Sendable {
    public static let minPitch: Float = 20
    public static let maxPitch: Float = 90

    public let limits: WorldMapLimits
    /// The ground point the camera looks at.
    public private(set) var focus: SIMD2<Float>
    public private(set) var height: Float
    public private(set) var pitch: Float

    public init(limits: WorldMapLimits, focus: SIMD2<Float>) {
        self.limits = limits
        self.focus = simd_clamp(focus, limits.minimum, limits.maximum)
        height = limits.maxHeight
        pitch = min(max(limits.initialPitch, Self.minPitch), Self.maxPitch)
    }

    /// Moves the focus by a ground distance, scaled by height so a pan feels the same zoomed.
    public mutating func pan(by delta: SIMD2<Float>) {
        focus = simd_clamp(
            focus + delta * (height / limits.maxHeight),
            limits.minimum,
            limits.maximum
        )
    }

    /// Positive zooms in.
    public mutating func zoom(by amount: Float) {
        height = min(max(height - amount, limits.minHeight), limits.maxHeight)
    }

    public mutating func tilt(by degrees: Float) {
        pitch = min(max(pitch + degrees, Self.minPitch), Self.maxPitch)
    }

    /// The camera position: `height` above the focus and back along the pitch.
    public var eye: SIMD3<Float> {
        let radians = pitch * .pi / 180
        let back = pitch >= Self.maxPitch ? 0 : height / tan(radians)
        return SIMD3(focus.x, focus.y - back, height)
    }
}
