// Points on an animated object's moving parts, so trap contact follows a blade's edge
// and not the pivot it turns about. See docs/engine/traps.md.

import OpenSkyFormatsCore
import simd

/// One mesh a rig bone moves: its skin and its rest bounds in skin space.
nonisolated public struct TrapContactPart: Sendable {
    public let skinning: SkinningPalette
    public let bounds: ModelBounds

    public init(skinning: SkinningPalette, bounds: ModelBounds) {
        self.skinning = skinning
        self.bounds = bounds
    }
}

/// Sample points of each moving part, in the space of the bone that moves it.
nonisolated public struct TrapContactShape: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public let bone: Int
        public let position: SIMD3<Float>
    }

    public let points: [Point]

    public static let empty = TrapContactShape(points: [])

    init(points: [Point]) {
        self.points = points
    }

    /// Only a mesh with one bone is a rigid part. A part whose bone is not in
    /// `boneNames` is left out.
    public init(boneNames: [String], parts: [TrapContactPart]) {
        let index = Dictionary(
            boneNames.enumerated().map { ($1.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        points = parts.flatMap { part -> [Point] in
            guard
                part.skinning.boneNames.count == 1,
                let name = part.skinning.boneNames.first,
                let bone = index[name.lowercased()],
                let toBone = part.skinning.skinToBoneMatrices.first
            else { return [] }
            return Self.samples(of: part.bounds).map { point in
                let local = toBone * SIMD4(point, 1)
                return Point(bone: bone, position: SIMD3(local.x, local.y, local.z))
            }
        }
    }

    /// The centre, the eight corners, and the six face centres of a box.
    static func samples(of bounds: ModelBounds) -> [SIMD3<Float>] {
        let low = bounds.min
        let high = bounds.max
        let centre = (low + high) / 2
        var result = [centre]
        for x in [low.x, high.x] {
            for y in [low.y, high.y] {
                for z in [low.z, high.z] {
                    result.append(SIMD3(x, y, z))
                }
            }
        }
        for axis in 0 ..< 3 {
            for end in [low, high] {
                var face = centre
                face[axis] = end[axis]
                result.append(face)
            }
        }
        return result
    }

    /// The points in the object's own space under the posed bone matrices. With
    /// no part, each bone's origin stands in.
    public func positions(posed bones: [simd_float4x4]) -> [SIMD3<Float>] {
        guard !points.isEmpty else {
            return bones.map { SIMD3($0.columns.3.x, $0.columns.3.y, $0.columns.3.z) }
        }
        return points.compactMap { point in
            guard bones.indices.contains(point.bone) else { return nil }
            let posed = bones[point.bone] * SIMD4(point.position, 1)
            return SIMD3(posed.x, posed.y, posed.z)
        }
    }
}
