// Fills a particle system's slot of its instance buffer each frame: square billboards,
// or ribbon bands for lightning (docs/rendering/particles.md).

import Metal
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyRenderCore
import simd

nonisolated extension ParticlePlayback {
    /// Writes the live particles into the slot's range. With a `viewer`, a blend that
    /// depends on order gets its particles far to near.
    public func prepareBuffer(slot: Int, viewer: SIMD3<Float>? = nil) -> (offset: Int, count: Int) {
        let simulator = simulator
        let offset = slot * max(capacity, 1) * MemoryLayout<ParticleGPUInstance>.stride
        guard simulator.isVisible, meshModel == nil else { return (offset, 0) }
        let instances = Array(instances(simulator, viewer: viewer).prefix(max(capacity, 1)))
        guard !instances.isEmpty else { return (offset, 0) }
        instances.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            instanceBuffer.contents().advanced(by: offset).copyMemory(
                from: base,
                byteCount: bytes.count
            )
        }
        return (offset, instances.count)
    }

    private func instances(
        _ simulator: ParticleSimulator, viewer: SIMD3<Float>?
    ) -> [ParticleGPUInstance] {
        if let lightning {
            let model = simulator.placementTransform * simulator.definition.worldTransform
            return lightning.segments(at: playbackTime, color: SIMD4(repeating: 1)).map {
                var segment = $0
                segment.start = Self.point(model, segment.start)
                segment.end = Self.point(model, segment.end)
                return segment.instance(alongTextureV: false)
            }
        }
        var particles = simulator.particles.map(Self.faded)
        guard !particles.isEmpty else { return [] }
        if let viewer, blendMode.dependsOnOrder {
            particles = ParticleDrawOrder.backToFront(particles, viewer: viewer, at: \.position)
        }
        let offsets = simulator.definition.subtextureOffsets
        return particles.map { particle in
            let uv = offsets.indices.contains(particle.atlasIndex)
                ? offsets[particle.atlasIndex] : SIMD4<Float>(0, 0, 1, 1)
            return ParticleGPUInstance(
                positionSize: SIMD4(particle.position, particle.radius),
                color: particle.color,
                uvRect: uv,
                rotation: SIMD4(cos(particle.rotation), sin(particle.rotation), 0, 0)
            )
        }
    }

    /// The particle with its birth and death fade in its alpha.
    private static func faded(_ particle: SimulatedParticle) -> SimulatedParticle {
        var faded = particle
        let fade = min(particle.age / 0.08, (particle.lifetime - particle.age) / 0.15, 1)
        faded.color *= SIMD4(1, 1, 1, max(fade, 0))
        return faded
    }

    private static func point(_ matrix: float4x4, _ point: SIMD3<Float>) -> SIMD3<Float> {
        let moved = matrix * SIMD4(point, 1)
        return SIMD3(moved.x, moved.y, moved.z)
    }

    /// The box around the live particles and their radii, nil with none alive. Mesh
    /// bounds are not used, because mod meshes often store wrong ones.
    public var liveBounds: ModelBounds? {
        if let lightning {
            return lightningBounds(lightning.parameters)
        }
        let particles = simulator.particles
        guard let first = particles.first else { return nil }
        var lower = first.position - first.radius
        var upper = first.position + first.radius
        for particle in particles.dropFirst() {
            lower = simd_min(lower, particle.position - particle.radius)
            upper = simd_max(upper, particle.position + particle.radius)
        }
        return ModelBounds(min: lower, max: upper)
    }

    /// The reach of a bolt: its length along +Y, widened by its bend and width.
    private func lightningBounds(_ bolt: ParticleLightning) -> ModelBounds {
        let simulator = simulator
        let model = simulator.placementTransform * simulator.definition.worldTransform
        let side = abs(bolt.arcOffset) + bolt.width
        let reach = bolt.length + abs(bolt.lengthVariation)
        var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var upper = -lower
        for corner in [SIMD3<Float>(-side, 0, -side), SIMD3(side, reach, side),
                       SIMD3(-side, reach, side), SIMD3(side, 0, -side)] {
            let point = Self.point(model, corner)
            lower = simd_min(lower, point)
            upper = simd_max(upper, point)
        }
        return ModelBounds(min: lower, max: upper)
    }
}
