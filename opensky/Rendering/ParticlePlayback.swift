// CPU particle playback + GPU billboard instance upload (M7.3.2). Immutable
// NIF definitions stay decoupled from this runtime; one playback belongs to
// one placed particle system and is retained by its resident RenderScene.
//
// Emitter/modifier semantics + alpha-function values:
// NifTools nif.xml (NiPSysEmitter, NiPSysModifier, AlphaFunction).
// https://github.com/niftools/nifxml/blob/develop/nif.xml

import Metal
import simd

nonisolated enum ParticleBlendMode: Equatable, Hashable {
    /// Source alpha over destination (SRC_ALPHA / INV_SRC_ALPHA).
    case alpha
    /// Emissive accumulation (SRC_ALPHA / ONE).
    case additive
    /// Full-color emissive accumulation (ONE / ONE).
    case additiveOne
    /// Destination modulation (DEST_COLOR / ZERO).
    case multiply

    init(alpha: NIFAlphaProperty?) {
        guard alpha?.blendEnabled == true else {
            self = .alpha
            return
        }
        switch (alpha?.sourceBlendMode, alpha?.destinationBlendMode) {
        case (6, 0): self = .additive
        case (0, 0): self = .additiveOne
        case (4, 1): self = .multiply
        default: self = .alpha
        }
    }
}

/// One active particle, wholly CPU-owned. Position + velocity are world-space
/// after birth, so static placed emitters need no later transform work.
nonisolated struct SimulatedParticle: Equatable {
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
    let color: SIMD4<Float>
    let initialRadius: Float
    var radius: Float
    var age: Float
    let lifetime: Float
    let atlasIndex: Int
}

/// Deterministic generator: stable frames/tests across processes and machines.
nonisolated private struct ParticleRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func unit() -> Float {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Float(value & 0x00FF_FFFF) / Float(0x0100_0000)
    }

    mutating func signed() -> Float {
        unit() * 2 - 1
    }
}

/// Pure simulation. Birth-rate controller blocks are not decoded in M7.3.1;
/// until they land, a bounded runtime policy fills roughly one quarter of the
/// system capacity per average lifetime. This is an OpenSky fallback, not a
/// claimed Creation Engine constant.
nonisolated struct ParticleSimulator {
    static let maximumCapacity = 2048

    let definition: ParticleSystemDefinition
    private(set) var placementTransform: float4x4
    let capacity: Int
    private(set) var particles: [SimulatedParticle] = []
    private var random: ParticleRandom
    private var birthAccumulator: Float = 0
    private var nextEmitter = 0

    init(definition: ParticleSystemDefinition, placementTransform: float4x4, seed: UInt64) {
        self.definition = definition
        self.placementTransform = placementTransform
        capacity = min(max(definition.maxParticles, 0), Self.maximumCapacity)
        random = ParticleRandom(seed: seed)
        particles.reserveCapacity(capacity)
    }

    mutating func reset(seed: UInt64) {
        particles.removeAll(keepingCapacity: true)
        random = ParticleRandom(seed: seed)
        birthAccumulator = 0
        nextEmitter = 0
    }

    /// Re-centers a camera-following emitter and its existing particles by
    /// the same world-space delta. Placed NIF emitters never call this path.
    mutating func translate(by delta: SIMD3<Float>) {
        placementTransform.columns.3 += SIMD4(delta, 0)
        for index in particles.indices {
            particles[index].position += delta
        }
    }

    mutating func advance(deltaTime: Float, wind: WindState, emissionScale: Float) {
        let deltaTime = simd_clamp(deltaTime, 0, 0.1)
        guard deltaTime > 0 else { return }
        updateExisting(deltaTime: deltaTime, wind: wind)
        emit(deltaTime: deltaTime, scale: max(emissionScale, 0))
    }

    private mutating func updateExisting(deltaTime: Float, wind: WindState) {
        let windVector = SIMD3(
            wind.direction.x * wind.speed,
            wind.direction.y * wind.speed,
            0
        )
        let activeModifiers = definition.modifiers.filter(\.active).sorted { $0.order < $1.order }
        for index in particles.indices.reversed() {
            particles[index].age += deltaTime
            if particles[index].age >= particles[index].lifetime {
                particles.remove(at: index)
                continue
            }
            for modifier in activeModifiers {
                switch modifier.kind {
                case let .gravity(axis, strength):
                    particles[index].velocity += axis * strength * deltaTime
                case let .wind(strength):
                    particles[index].velocity += windVector * strength * deltaTime
                case let .scale(scales):
                    particles[index].radius = scaledRadius(
                        initial: particles[index].initialRadius,
                        scales: scales,
                        fraction: particles[index].age / particles[index].lifetime
                    )
                default:
                    break
                }
            }
            particles[index].position += particles[index].velocity * deltaTime
        }
    }

    private mutating func emit(deltaTime: Float, scale: Float) {
        let emitters = definition.emitters.filter(\.active)
        guard capacity > 0, !emitters.isEmpty, particles.count < capacity, scale > 0 else { return }
        let averageLife = max(
            emitters.reduce(0) { $0 + max($1.lifeSpan, 0.1) }
                / Float(emitters.count),
            0.1
        )
        let fallbackRate = simd_clamp(Float(capacity) * 0.25 / averageLife, 6, 60)
        birthAccumulator += fallbackRate * scale * deltaTime
        let births = min(Int(birthAccumulator), capacity - particles.count)
        birthAccumulator -= Float(births)
        for _ in 0 ..< births {
            let emitter = emitters[nextEmitter % emitters.count]
            nextEmitter += 1
            particles.append(makeParticle(emitter: emitter))
        }
    }

    private mutating func makeParticle(emitter: ParticleEmitter) -> SimulatedParticle {
        let modelTransform = placementTransform * definition.worldTransform
        let localPosition = samplePosition(shape: emitter.shape)
        let worldPosition4 = modelTransform * SIMD4(localPosition, 1)
        let declination = emitter.declination + random.signed() * emitter.declinationVariation
        let planar = emitter.planarAngle + random.signed() * emitter.planarAngleVariation
        let localDirection = SIMD3(
            sin(declination) * cos(planar),
            sin(declination) * sin(planar),
            cos(declination)
        )
        let worldVelocity4 = modelTransform * SIMD4(localDirection, 0)
        let transformedDirection = SIMD3(
            worldVelocity4.x, worldVelocity4.y, worldVelocity4.z
        )
        let directionLength = simd_length(transformedDirection)
        let direction = directionLength > .ulpOfOne
            ? transformedDirection / directionLength : SIMD3<Float>(0, 0, 1)
        let speed = max(emitter.speed + random.signed() * emitter.speedVariation, 0)
        let lifetime = max(emitter.lifeSpan + random.signed() * emitter.lifeSpanVariation, 0.01)
        let radius = max(emitter.initialRadius + random.signed() * emitter.radiusVariation, 0.01)
        let atlasCount = max(definition.subtextureOffsets.count, 1)
        return SimulatedParticle(
            position: SIMD3(worldPosition4.x, worldPosition4.y, worldPosition4.z),
            velocity: direction * speed,
            color: emitter.initialColor,
            initialRadius: radius,
            radius: radius,
            age: 0,
            lifetime: lifetime,
            atlasIndex: min(Int(random.unit() * Float(atlasCount)), atlasCount - 1)
        )
    }

    private mutating func samplePosition(shape: ParticleEmitter.Shape) -> SIMD3<Float> {
        switch shape {
        case let .box(width, height, depth):
            return SIMD3(random.signed() * width, random.signed() * height, random.signed() * depth)
                * 0.5
        case let .cylinder(radius, height):
            let angle = random.unit() * 2 * Float.pi
            let distance = sqrt(random.unit()) * radius
            return SIMD3(
                cos(angle) * distance,
                sin(angle) * distance,
                random.signed() * height * 0.5
            )
        case let .sphere(radius):
            let z = random.signed()
            let angle = random.unit() * 2 * Float.pi
            let radial = pow(random.unit(), 1 / 3 as Float) * radius
            let xy = sqrt(max(1 - z * z, 0))
            return SIMD3(xy * cos(angle), xy * sin(angle), z) * radial
        case .mesh:
            // M7.3.1 retains mesh refs, not mesh vertices. Emit from origin
            // until mesh-surface sampling gains an engine-side geometry link.
            return .zero
        }
    }

    private func scaledRadius(initial: Float, scales: [Float], fraction: Float) -> Float {
        guard let first = scales.first else { return initial }
        guard scales.count > 1 else { return max(initial * first, 0.01) }
        let position = simd_clamp(fraction, 0, 1) * Float(scales.count - 1)
        let lower = min(Int(position), scales.count - 1)
        let upper = min(lower + 1, scales.count - 1)
        let scale = scales[lower] * (1 - position.truncatingRemainder(dividingBy: 1))
            + scales[upper] * position.truncatingRemainder(dividingBy: 1)
        return max(initial * scale, 0.01)
    }
}

/// Layout mirrored by ParticleInstance in ShaderTypes.h.
nonisolated struct ParticleGPUInstance {
    let positionSize: SIMD4<Float>
    let color: SIMD4<Float>
    let uvRect: SIMD4<Float>
}

nonisolated final class ParticlePlayback {
    let name: String
    let sourcePath: String
    let texture: MTLTexture
    let blendMode: ParticleBlendMode
    let instanceBuffer: MTLBuffer
    let capacity: Int
    let emitterCount: Int
    private let seed: UInt64
    private(set) var simulator: ParticleSimulator
    private(set) var simulationTime: Float = 0

    var liveCount: Int {
        simulator.particles.count
    }

    init(
        device: MTLDevice,
        definition: ParticleSystemDefinition,
        placementTransform: float4x4,
        texture: MTLTexture,
        seed: UInt64,
        sourcePath: String = "(synthetic)"
    ) throws {
        name = definition.name ?? "Unnamed emitter"
        self.sourcePath = sourcePath
        self.texture = texture
        blendMode = ParticleBlendMode(alpha: definition.alphaProperty)
        self.seed = seed
        simulator = ParticleSimulator(
            definition: definition,
            placementTransform: placementTransform,
            seed: seed
        )
        capacity = simulator.capacity
        emitterCount = definition.emitters.filter(\.active).count
        let count = max(capacity, 1) * Renderer.maxFramesInFlight
        guard
            let buffer = device.makeBuffer(
                length: count * MemoryLayout<ParticleGPUInstance>.stride,
                options: .storageModeShared
            ) else { throw RendererError.bufferAllocationFailed }
        buffer.label = "Particle instances: \(name)"
        instanceBuffer = buffer
    }

    func advance(deltaTime: Float, wind: WindState, emissionScale: Float) {
        simulator.advance(deltaTime: deltaTime, wind: wind, emissionScale: emissionScale)
        simulationTime += max(deltaTime, 0)
    }

    func translate(by delta: SIMD3<Float>) {
        simulator.translate(by: delta)
    }

    func reset() {
        simulator.reset(seed: seed)
        simulationTime = 0
    }

    func seek(to time: Float, wind: WindState, emissionScale: Float) {
        let target = max(time, 0)
        simulator.reset(seed: seed)
        simulationTime = 0
        while simulationTime + 0.05 < target {
            simulator.advance(deltaTime: 0.05, wind: wind, emissionScale: emissionScale)
            simulationTime += 0.05
        }
        let remainder = target - simulationTime
        simulator.advance(deltaTime: remainder, wind: wind, emissionScale: emissionScale)
        simulationTime = target
    }

    func prepareBuffer(slot: Int) -> (offset: Int, count: Int) {
        let particles = simulator.particles
        let offset = slot * max(capacity, 1) * MemoryLayout<ParticleGPUInstance>.stride
        guard !particles.isEmpty else { return (offset, 0) }
        let offsets = simulator.definition.subtextureOffsets
        let instances = particles.map { particle in
            let uv = offsets.indices.contains(particle.atlasIndex)
                ? offsets[particle.atlasIndex] : SIMD4<Float>(0, 0, 1, 1)
            let fade = min(particle.age / 0.08, (particle.lifetime - particle.age) / 0.15, 1)
            return ParticleGPUInstance(
                positionSize: SIMD4(particle.position, particle.radius),
                color: particle.color * SIMD4(1, 1, 1, max(fade, 0)),
                uvRect: uv
            )
        }
        instances.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            instanceBuffer.contents().advanced(by: offset).copyMemory(
                from: base,
                byteCount: bytes.count
            )
        }
        return (offset, instances.count)
    }
}
