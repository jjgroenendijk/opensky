// Picks a birth point on a mesh emitter's geometry by its nif.xml `EmitFrom`
// mode. A mesh with no triangles uses its vertices; one with no vertices, the origin.

import OpenSkyFormatsMesh
import simd

nonisolated public struct MeshEmitterSampler: Sendable {
    public struct Point: Equatable, Sendable {
        public let position: SIMD3<Float>
        /// Nil when the mesh stores no normals and the face has no area.
        public let normal: SIMD3<Float>?
    }

    public let source: MeshEmitterSource

    public init(source: MeshEmitterSource) {
        self.source = source
    }

    /// `unit` returns a value in 0 ..< 1 for each random choice.
    public func sample(_ unit: () -> Float) -> Point {
        guard !source.positions.isEmpty else { return Point(position: .zero, normal: nil) }
        guard !source.triangles.isEmpty, source.emitFrom != .vertices else {
            return vertex(pick(source.positions.count, unit))
        }
        let triangle = source.triangles[pick(source.triangles.count, unit)]
        let corners = [Int(triangle.x), Int(triangle.y), Int(triangle.z)]
        switch source.emitFrom {
        case .vertices:
            return vertex(corners[pick(3, unit)])
        case .faceCenter:
            return face(corners, weights: SIMD3(repeating: 1 / 3))
        case .faceSurface:
            var first = unit()
            var second = unit()
            if first + second > 1 {
                first = 1 - first
                second = 1 - second
            }
            return face(corners, weights: SIMD3(1 - first - second, first, second))
        case .edgeCenter, .edgeSurface:
            let edge = pick(3, unit)
            let along = source.emitFrom == .edgeCenter ? 0.5 : unit()
            var weights = SIMD3<Float>.zero
            weights[edge] = 1 - along
            weights[(edge + 1) % 3] = along
            return face(corners, weights: weights)
        }
    }

    private func pick(_ count: Int, _ unit: () -> Float) -> Int {
        min(Int(unit() * Float(count)), count - 1)
    }

    private func vertex(_ index: Int) -> Point {
        Point(position: source.positions[index], normal: normal(at: index))
    }

    private func face(_ corners: [Int], weights: SIMD3<Float>) -> Point {
        let points = corners.map { source.positions[$0] }
        let position = points[0] * weights.x + points[1] * weights.y + points[2] * weights.z
        let stored = corners.compactMap(normal(at:))
        let blended = stored.count == 3
            ? stored[0] * weights.x + stored[1] * weights.y + stored[2] * weights.z
            : simd_cross(points[1] - points[0], points[2] - points[0])
        let length = simd_length(blended)
        return Point(position: position, normal: length > 1e-6 ? blended / length : nil)
    }

    private func normal(at index: Int) -> SIMD3<Float>? {
        source.normals.indices.contains(index) ? source.normals[index] : nil
    }
}
