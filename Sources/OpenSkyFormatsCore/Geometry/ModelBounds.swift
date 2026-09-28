import simd

/// Axis-aligned bounds in model space, captured from CPU-side vertex data at
/// load time (vertices live only on the GPU afterwards). Scene build (todo
/// 2.7) pushes the 8 corners through each instance transform to accumulate a
/// world AABB for camera placement.
nonisolated public struct ModelBounds: Equatable, Sendable {
    public let min: SIMD3<Float>
    public let max: SIMD3<Float>

    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    /// The 8 corner points, for pushing through an affine transform.
    public var corners: [SIMD3<Float>] {
        [min.x, max.x].flatMap { x in
            [min.y, max.y].flatMap { y in
                [min.z, max.z].map { z in SIMD3(x, y, z) }
            }
        }
    }

    public func union(_ other: ModelBounds) -> ModelBounds {
        ModelBounds(min: simd_min(min, other.min), max: simd_max(max, other.max))
    }

    /// Nil for an empty point set.
    public static func containing(_ points: [SIMD3<Float>]) -> ModelBounds? {
        guard let first = points.first else { return nil }
        var lower = first
        var upper = first
        for point in points.dropFirst() {
            lower = simd_min(lower, point)
            upper = simd_max(upper, point)
        }
        return ModelBounds(min: lower, max: upper)
    }

    /// Union of each mesh's local vertex AABB pushed through its
    /// mesh -> model transform. Nil when no mesh carries positions.
    public static func containing(model: Model) -> ModelBounds? {
        var result: ModelBounds?
        for mesh in model.meshes {
            guard let local = containing(mesh.positions) else { continue }
            let inModelSpace = local.transformed(by: mesh.transform)
            result = result.map { $0.union(inModelSpace) } ?? inModelSpace
        }
        return result
    }

    /// AABB of this box under an affine transform: all 8 corners pushed
    /// through, re-boxed. Conservative under rotation — exact enough for
    /// camera framing.
    public func transformed(by matrix: float4x4) -> ModelBounds {
        let moved = corners.map { corner in
            let out = matrix * SIMD4(corner, 1)
            return SIMD3(out.x, out.y, out.z)
        }
        // corners is never empty, so containing cannot return nil.
        return Self.containing(moved) ?? self
    }
}
