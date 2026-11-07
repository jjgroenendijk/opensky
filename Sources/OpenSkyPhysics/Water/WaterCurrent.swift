// One water current and the list a water box carries. Rules from the game's
// behaviour; see docs/engine/water-physics.md#current-lists.

import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import simd

/// Where a current applies inside its water box.
nonisolated public enum WaterCurrentShape: Equatable, Sendable {
    /// Kind 0: the whole box, at full strength.
    case everywhere
    /// Kind 1: a vertical cylinder around a world xy centre.
    case cylinder(centre: SIMD2<Float>, radius: Float)
    /// Kind 3: the side of a plane away from its normal, within `radius` horizontally.
    case plane(point: SIMD3<Float>, normal: SIMD3<Float>, radius: Float)
}

/// One current. Velocities are game units per second, positions game units.
nonisolated public struct WaterCurrent: Equatable, Sendable {
    public var shape: WaterCurrentShape
    public var linear: SIMD3<Float>
    /// Read but not applied: the game turns no actor with it.
    public var angular: SIMD3<Float>
    /// The strength at the shape's edge, from 0 to 1.
    public var edgeStrength: Float
    /// x is a speed around the centre and y a speed away from it.
    public var isRadial: Bool

    public init(
        shape: WaterCurrentShape, linear: SIMD3<Float>, angular: SIMD3<Float> = .zero,
        edgeStrength: Float = 0, isRadial: Bool = false
    ) {
        self.shape = shape
        self.linear = linear
        self.angular = angular
        self.edgeStrength = edgeStrength
        self.isRadial = isRadial
    }

    /// The share of this current at `point`, or nil outside its shape.
    public func strength(at point: SIMD3<Float>) -> Float? {
        let falloff: Float
        switch shape {
        case .everywhere:
            return 1
        case let .cylinder(centre, radius):
            guard radius > 0 else { return nil }
            falloff = (radius - simd_distance(SIMD2(point.x, point.y), centre)) / radius
        case let .plane(planePoint, normal, radius):
            guard radius > 0, simd_dot(point - planePoint, normal) <= 0 else { return nil }
            let offset = SIMD2(point.x - planePoint.x, point.y - planePoint.y)
            falloff = (radius - simd_length(offset)) / radius
        }
        guard falloff > 0 else { return nil }
        return min(falloff, 1) * (1 - edgeStrength) + edgeStrength
    }

    /// The current's own velocity at `point`, before strength.
    public func velocity(at point: SIMD3<Float>) -> SIMD3<Float> {
        guard isRadial, let centre else { return linear }
        let outward = SIMD2(point.x - centre.x, point.y - centre.y)
        let length = simd_length(outward)
        guard length > 0 else { return SIMD3(0, 0, linear.z) }
        let away = outward / length
        let around = SIMD2(-away.y, away.x)
        let flat = around * linear.x + away * linear.y
        return SIMD3(flat.x, flat.y, linear.z)
    }

    private var centre: SIMD2<Float>? {
        switch shape {
        case .everywhere: nil
        case let .cylinder(centre, _): centre
        case let .plane(point, _, _): SIMD2(point.x, point.y)
        }
    }
}

nonisolated extension [WaterCurrent] {
    /// Kind 0 currents add; a shaped current blends over the sum so far by its strength.
    public func velocity(at point: SIMD3<Float>) -> SIMD3<Float> {
        var result = SIMD3<Float>.zero
        for current in self {
            guard let strength = current.strength(at: point) else { continue }
            if current.shape == .everywhere {
                result += current.velocity(at: point)
            } else {
                result = simd_mix(result, current.velocity(at: point), SIMD3(repeating: strength))
            }
        }
        return result
    }
}

nonisolated public enum WaterCurrentList {
    static let havokScale = NIFCollisionModel.havokToEngineScale

    /// The currents of an `XWCU` list, in Havok units, as game-unit currents. Decoding
    /// stops at the first kind it does not know, because its length is unknown.
    public static func decode(_ vectors: [CellExtras.WaterVelocity]) -> [WaterCurrent] {
        var currents: [WaterCurrent] = []
        var index = 0
        while index + 2 < vectors.count {
            let kind = Int32(bitPattern: vectors[index + 2].unknown.bitPattern)
            let first = vectors[index], second = vectors[index + 1], third = vectors[index + 2]
            let shape: WaterCurrentShape
            switch kind {
            case 0:
                shape = .everywhere
                index += 3
            case 1:
                shape = .cylinder(
                    centre: SIMD2(third.velocity.x, third.velocity.y) * havokScale,
                    radius: third.velocity.z * havokScale
                )
                index += 3
            case 3 where index + 3 < vectors.count:
                let fourth = vectors[index + 3]
                shape = .plane(
                    point: third.velocity * havokScale, normal: fourth.velocity,
                    radius: fourth.unknown * havokScale
                )
                index += 4
            default:
                return currents
            }
            currents.append(WaterCurrent(
                shape: shape, linear: first.velocity * havokScale,
                angular: second.velocity, edgeStrength: min(max(second.unknown, 0), 1),
                isRadial: first.unknown != 0
            ))
        }
        return currents
    }

    /// The default plane speed when a reference has no `XCVL`, in Havok units.
    public static let defaultPlaneLinear = SIMD3<Float>(0, 6, 0)

    /// One `CurrentPlane` shape as a kind 3 current. `shape` is the shape's world
    /// transform; `linear` is the reference's `XCVL` in Havok units.
    public static func plane(
        shape: float4x4, boundRadius: Float, linear: SIMD3<Float>?, angular: SIMD3<Float>?
    ) -> WaterCurrent {
        let authored = linear ?? .zero
        let local = authored == .zero ? defaultPlaneLinear : authored
        let rotation = simd_float3x3(
            simd_normalize(shape.columns.0.xyz), simd_normalize(shape.columns.1.xyz),
            simd_normalize(shape.columns.2.xyz)
        )
        let point = shape.columns.3.xyz + SIMD3(0, 0, 0.5 * havokScale)
        return WaterCurrent(
            shape: .plane(point: point, normal: rotation.columns.2, radius: boundRadius),
            linear: rotation * local * havokScale, angular: angular ?? .zero
        )
    }
}
