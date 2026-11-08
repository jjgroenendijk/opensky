// A mesh particle system draws its pool's meshes at each live particle, turned about the
// particle's own axis and scaled by its size. See docs/formats/nif-particles.md#mesh-particles.

import OpenSkyRenderCore
import simd

nonisolated extension ParticlePlayback {
    /// One placement of the pool's meshes per live particle; empty for a billboard system.
    public func meshPlacements() -> [RenderPlacement] {
        guard let meshModel else { return [] }
        let simulator = simulator
        guard simulator.isVisible else { return [] }
        return simulator.particles.map { particle in
            RenderPlacement(
                model: meshModel, transform: Self.meshTransform(of: particle),
                castsShadows: false, layer: .particles
            )
        }
    }

    /// Where a mesh particle draws: at its position, turned by its angle about its axis.
    static func meshTransform(of particle: SimulatedParticle) -> float4x4 {
        let axis = simd_length_squared(particle.axis) > 1e-8
            ? simd_normalize(particle.axis) : SIMD3<Float>(0, 0, 1)
        let turn = float4x4(simd_quatf(angle: particle.rotation, axis: axis))
        var matrix = turn * float4x4(diagonal: SIMD4(SIMD3(repeating: particle.radius), 1))
        matrix.columns.3 = SIMD4(particle.position, 1)
        return matrix
    }
}
