// Water as boxes: a cell's water, a placed water activator, or a current plane's
// box. See docs/engine/water-physics.md#where-the-boxes-come-from.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import simd

/// One water box in world space.
nonisolated public struct WaterVolume: Sendable {
    public let transform: float4x4
    public let halfExtents: SIMD3<Float>
    /// Nil for a current plane's box, which holds no swimmable water.
    public let surface: Float?
    public let currents: [WaterCurrent]
    public let waterType: FormID?
    /// `WATR` flag 0x1.
    public let isDangerous: Bool
    public let bounds: ModelBounds
    private let inverse: float4x4

    public init?(
        transform: float4x4, halfExtents: SIMD3<Float>, surface: Float?,
        currents: [WaterCurrent], waterType: FormID? = nil, isDangerous: Bool = false
    ) {
        guard halfExtents.min() > 0, abs(transform.determinant) > 1e-9 else { return nil }
        self.transform = transform
        self.halfExtents = halfExtents
        self.surface = surface
        self.currents = currents
        self.waterType = waterType
        self.isDangerous = isDangerous
        inverse = transform.inverse
        bounds = Self.worldBounds(transform: transform, halfExtents: halfExtents)
    }

    /// Inside the box, or below it when `ignoringTop` is set. A point above the
    /// surface still finds the surface this way, for the swim and splash tests.
    public func contains(_ point: SIMD3<Float>, ignoringTop: Bool = false) -> Bool {
        let local = inverse * SIMD4(point, 1)
        let extents = halfExtents
        guard abs(local.x) <= extents.x, abs(local.y) <= extents.y, local.z >= -extents.z
        else { return false }
        return ignoringTop || local.z <= extents.z
    }

    private static func worldBounds(
        transform: float4x4, halfExtents: SIMD3<Float>
    ) -> ModelBounds {
        let corners = ModelBounds(min: -halfExtents, max: halfExtents).corners.map {
            let world = transform * SIMD4($0, 1)
            return SIMD3(world.x, world.y, world.z)
        }
        return ModelBounds(
            min: corners.reduce(SIMD3(repeating: .infinity)) { simd_min($0, $1) },
            max: corners.reduce(SIMD3(repeating: -.infinity)) { simd_max($0, $1) }
        )
    }
}

/// What the water is at one point.
nonisolated public struct WaterReading: Equatable, Sendable {
    public var surface: Float
    public var current: SIMD3<Float>
    public var waterType: FormID?
    public var isDangerous: Bool

    public init(
        surface: Float, current: SIMD3<Float> = .zero, waterType: FormID? = nil,
        isDangerous: Bool = false
    ) {
        self.surface = surface
        self.current = current
        self.waterType = waterType
        self.isDangerous = isDangerous
    }
}

/// The water boxes of one cell.
nonisolated public struct WaterVolumeSet: Sendable {
    public let volumes: [WaterVolume]
    public let bounds: ModelBounds?
    private let index: BoundsSpatialIndex

    public static let empty = WaterVolumeSet(volumes: [])

    public init(volumes: [WaterVolume]) {
        self.volumes = volumes
        index = BoundsSpatialIndex(bounds: volumes.map(\.bounds))
        bounds = volumes.dropFirst().reduce(volumes.first?.bounds) { merged, volume in
            merged.map {
                ModelBounds(
                    min: simd_min($0.min, volume.bounds.min), max: simd_max(
                        $0.max,
                        volume.bounds.max
                    )
                )
            }
        }
    }

    /// The boxes whose footprint holds `point`, whatever its height under the top.
    public func candidates(at point: SIMD3<Float>) -> [WaterVolume] {
        guard let bounds, Self.footprint(bounds, holds: point) else { return [] }
        let probe = ModelBounds(
            min: SIMD3(point.x, point.y, -.infinity), max: SIMD3(point.x, point.y, .infinity)
        )
        return index.query(overlapping: probe).map { volumes[$0] }
    }

    private static func footprint(_ bounds: ModelBounds, holds point: SIMD3<Float>) -> Bool {
        point.x >= bounds.min.x && point.x <= bounds.max.x
            && point.y >= bounds.min.y && point.y <= bounds.max.y
    }
}

nonisolated extension Sequence<WaterVolume> {
    /// The highest surface over `point`, with the current at it. A current plane's box
    /// that holds the point blends its currents over that water's own.
    public func sample(at point: SIMD3<Float>) -> WaterReading? {
        var best: WaterVolume?
        var planes: [WaterCurrent] = []
        for volume in self where volume.contains(point, ignoringTop: volume.surface != nil) {
            guard let surface = volume.surface else {
                planes += volume.currents
                continue
            }
            if best?.surface.map({ surface > $0 }) ?? true {
                best = volume
            }
        }
        guard let best, let surface = best.surface else { return nil }
        let current = point.z <= surface ? (best.currents + planes).velocity(at: point) : .zero
        return WaterReading(
            surface: surface, current: current, waterType: best.waterType,
            isDangerous: best.isDangerous
        )
    }
}

nonisolated extension [WaterVolumeSet] {
    public func water(at point: SIMD3<Float>) -> WaterReading? {
        flatMap { $0.candidates(at: point) }.sample(at: point)
    }
}
