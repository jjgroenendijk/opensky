// The pick Papyrus `PlayImpactEffect` casts: a straight line from a reference or node,
// ending on the first surface (<https://ck.uesp.net/wiki/PlayImpactEffect_-_ObjectReference>).
// Pure: the caller passes the static hit and the terrain heights.

import Foundation
import OpenSkyFormatsESM
import simd

/// Where a pick meets a surface, and that surface's `MATT`.
nonisolated public struct ImpactPickHit: Equatable, Sendable {
    public let position: SIMD3<Float>
    public let material: FormID?

    public init(position: SIMD3<Float>, material: FormID?) {
        self.position = position
        self.material = material
    }
}

nonisolated public enum ImpactPick {
    /// Terrain is tested this often along the line, in units. OpenSky's value.
    public static let terrainStep: Float = 16

    /// The nearer of the static hit and the first point at or below the terrain.
    /// - Parameters:
    ///   - staticHit: the first static collision along the line, with its distance.
    ///   - terrain: the ground height and `MATT` under a point; nil where none is.
    public static func resolve(
        origin: SIMD3<Float>, direction: SIMD3<Float>, length: Float,
        staticHit: (distance: Float, hit: ImpactPickHit)?,
        terrain: (SIMD2<Float>) -> (height: Float, material: FormID?)?
    ) -> ImpactPickHit? {
        let squared = simd_length_squared(direction)
        guard length.isFinite, length > 0, squared.isFinite, squared > 0 else { return nil }
        let unit = direction / squared.squareRoot()
        let limit = min(length, staticHit?.distance ?? length)
        var travelled: Float = 0
        while travelled <= limit {
            let point = origin + unit * travelled
            if let ground = terrain(SIMD2(point.x, point.y)), point.z <= ground.height {
                return ImpactPickHit(
                    position: SIMD3(point.x, point.y, ground.height), material: ground.material
                )
            }
            travelled += terrainStep
        }
        return staticHit?.hit
    }
}
