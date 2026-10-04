// The 3D logo the game shows behind the main menu movie, in place of the world.
// See docs/engine/main-menu.md.

import Foundation
import simd

nonisolated public enum TitleBackdrop: Sendable {
    public static let logoPath = "meshes\\interface\\logo\\logo.nif"
    /// How many bounding radii in front of the camera the logo floats.
    public static let distanceInRadii: Float = 2.2

    /// Faces the logo's front (its +Y side) to the camera and centers its bounds
    /// on the view line. `right` and `forward` are the camera's unit vectors.
    public static func transform(
        eye: SIMD3<Float>, forward: SIMD3<Float>, right: SIMD3<Float>,
        boundsMin: SIMD3<Float>, boundsMax: SIMD3<Float>
    ) -> float4x4 {
        let up = simd_normalize(simd_cross(right, forward))
        let rotation = float3x3(columns: (-right, -forward, up))
        let center = (boundsMin + boundsMax) / 2
        let radius = max(1, simd_length(boundsMax - boundsMin) / 2)
        let target = eye + forward * radius * distanceInRadii
        let origin = target - rotation * center
        return float4x4(columns: (
            SIMD4(-right, 0), SIMD4(-forward, 0), SIMD4(up, 0), SIMD4(origin, 1)
        ))
    }
}
