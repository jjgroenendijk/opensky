// The 3D logo and smoke the game shows behind the main menu movie, in place of
// the world. See docs/engine/main-menu.md.

import Foundation
import simd

nonisolated public enum TitleBackdrop: Sendable {
    public static let logoPath = "meshes\\interface\\logo\\logo.nif"
    /// The model of the `INTMenuFogParticles` STAT in `Skyrim.esm`.
    public static let fogPath = "meshes\\interface\\intmenufogparticles.nif"
    /// How many bounding radii in front of the camera the logo floats.
    public static let distanceInRadii: Float = 2.2

    /// The camera the backdrop faces. `right` and `forward` are unit vectors.
    public struct View: Equatable, Sendable {
        public let eye: SIMD3<Float>
        public let forward: SIMD3<Float>
        public let right: SIMD3<Float>

        public init(eye: SIMD3<Float>, forward: SIMD3<Float>, right: SIMD3<Float>) {
            self.eye = eye
            self.forward = forward
            self.right = right
        }
    }

    /// A model's bounds in its own space.
    public struct Box: Equatable, Sendable {
        public let min: SIMD3<Float>
        public let max: SIMD3<Float>

        public init(min: SIMD3<Float>, max: SIMD3<Float>) {
            self.min = min
            self.max = max
        }

        var center: SIMD3<Float> {
            (min + max) / 2
        }

        var radius: Float {
            Swift.max(1, simd_length(max - min) / 2)
        }
    }

    /// Faces the logo's front (its +Y side) to the camera and centers its bounds
    /// on the view line.
    public static func logoTransform(view: View, logo: Box) -> float4x4 {
        facing(view, center: logo.center, at: view.eye + view.forward * logoDistance(logo))
    }

    /// Puts the smoke volume just behind the logo, so the camera stands outside it.
    /// [WARNING] The game's placement is not confirmed.
    public static func fogTransform(view: View, logo: Box, fog: Box) -> float4x4 {
        let depth = (fog.max.y - fog.min.y) / 2
        let target = view.eye + view.forward * (logoDistance(logo) + depth)
        return facing(view, center: fog.center, at: target)
    }

    private static func logoDistance(_ logo: Box) -> Float {
        logo.radius * distanceInRadii
    }

    /// Maps model +Y to the camera and puts the model point `center` at `target`.
    private static func facing(
        _ view: View, center: SIMD3<Float>, at target: SIMD3<Float>
    ) -> float4x4 {
        let up = simd_normalize(simd_cross(view.right, view.forward))
        let rotation = float3x3(columns: (-view.right, -view.forward, up))
        let origin = target - rotation * center
        return float4x4(columns: (
            SIMD4(-view.right, 0), SIMD4(-view.forward, 0), SIMD4(up, 0), SIMD4(origin, 1)
        ))
    }
}
