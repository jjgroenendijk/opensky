// CPU particle playback and GPU billboard upload. One playback per placed particle
// system, held by its `RenderScene`. Emitter, modifier and alpha-function semantics:
// NifTools nif.xml (https://github.com/niftools/nifxml/blob/develop/nif.xml).

@preconcurrency @unsafe public import Metal
import OpenSkyFormatsCore
public import OpenSkyFormatsMesh
public import OpenSkyRenderCore
public import OpenSkyRenderResources
import OpenSkyShaderTypes
public import simd
import Synchronization

nonisolated public enum ParticleBlendMode: Equatable, Hashable, Sendable {
    /// Source alpha over destination (SRC_ALPHA / INV_SRC_ALPHA).
    case alpha
    /// Emissive accumulation (SRC_ALPHA / ONE).
    case additive
    /// Full-color emissive accumulation (ONE / ONE).
    case additiveOne
    /// Destination modulation (DEST_COLOR / ZERO).
    case multiply

    /// The blend adds to the frame, so fog takes the added light away instead.
    var addsLight: Bool {
        self == .additive || self == .additiveOne
    }

    /// Additive blends sum, so their draw order does not change the image.
    var dependsOnOrder: Bool {
        self == .alpha || self == .multiply
    }

    public init(alpha: NIFAlphaProperty?) {
        guard let alpha, alpha.blendEnabled else {
            self = .alpha
            return
        }
        self.init(blend: NIFBlend(
            source: alpha.sourceBlendMode, destination: alpha.destinationBlendMode
        ))
    }

    public init(blend: NIFBlend) {
        switch (blend.source, blend.destination) {
        case (6, 0): self = .additive
        case (0, 0): self = .additiveOne
        case (4, 1): self = .multiply
        default: self = .alpha
        }
    }
}

/// One active particle, wholly CPU-owned. Position + velocity are world-space
/// after birth, so static placed emitters need no later transform work.
nonisolated public struct SimulatedParticle: Equatable, Sendable {
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
    let initialColor: SIMD4<Float>
    var color: SIMD4<Float>
    let initialRadius: Float
    var radius: Float
    var age: Float
    var lifetime: Float
    var atlasIndex: Int
    /// Radians the billboard is turned, and radians per second.
    var rotation: Float = 0
    var rotationSpeed: Float = 0
    /// The axis a mesh particle spins about, unit length. A billboard turns in the screen
    /// plane and ignores it.
    var axis = SIMD3<Float>(0, 0, 1)
    /// The number of spawns before this particle.
    var generation: UInt16 = 0
    /// The sub-texture start frame, loop start frame, and frame count this particle drew.
    var frames = SIMD3<Float>.zero
}

/// Pure simulation. An emitter with a `NiPSysEmitterCtlr` births at its keyed rate.
/// One without falls back to about a quarter of capacity per average lifetime, an
/// OpenSky choice and not an engine constant.
nonisolated public struct ParticleSimulator: Sendable {
    public static let maximumCapacity = 2048

    public let definition: ParticleSystemDefinition
    public private(set) var placementTransform: float4x4
    public let capacity: Int
    public private(set) var particles: [SimulatedParticle] = []
    /// Scales new particles' speed and size. A faster particle lives shorter, so it
    /// still crosses the same distance. Existing particles keep their values.
    var spawnScale = PrecipitationScale.identity
    /// Seconds simulated since the last reset or sequence switch; the controllers' clock.
    public private(set) var elapsed: Float = 0
    /// The controllers that play now: the default sequence's, or the played sequence's.
    public private(set) var controllers: ParticleControllerSet
    /// The lowercased sequence an effect graph last played; nil plays the default.
    public internal(set) var sequence: String?
    var random: ParticleRandom
    /// The active modifiers of the current step, with their controllers applied.
    private(set) var activeModifiers: [ParticleModifier] = []
    /// World units per second the emitter moved during the last step.
    private(set) var emitterVelocity = SIMD3<Float>.zero
    private var pendingDisplacement = SIMD3<Float>.zero
    /// World units per second the inherit object moved during the last step.
    private(set) var inheritVelocity = SIMD3<Float>.zero
    private var pendingInheritDisplacement = SIMD3<Float>.zero
    /// Where the inherit object was at the last move.
    private var inheritPosition: SIMD3<Float>?
    /// The moved nodes of the model at the last move: each node's change from its rest,
    /// in the model frame, by lowercased name.
    private(set) var nodeDeltas: [String: float4x4] = [:]
    private var birthAccumulator: Float = 0
    private var controlledAccumulators: [Float] = []
    private var nextEmitter = 0

    public init(definition: ParticleSystemDefinition, placementTransform: float4x4, seed: UInt64) {
        self.definition = definition
        self.placementTransform = placementTransform
        capacity = min(max(definition.maxParticles, 0), Self.maximumCapacity)
        controllers = definition.defaultControllers
        random = ParticleRandom(seed: seed)
        particles.reserveCapacity(capacity)
    }

    public mutating func reset(seed: UInt64) {
        particles.removeAll(keepingCapacity: true)
        random = ParticleRandom(seed: seed)
        birthAccumulator = 0
        controlledAccumulators.removeAll()
        nextEmitter = 0
        elapsed = 0
        controllers = definition.defaultControllers
        sequence = nil
        activeModifiers = []
        emitterVelocity = .zero
        pendingDisplacement = .zero
        inheritVelocity = .zero
        pendingInheritDisplacement = .zero
        inheritPosition = nil
    }

    /// Re-centers a camera-following emitter and its existing particles by
    /// the same world-space delta. Placed NIF emitters never call this path.
    mutating func translate(by delta: SIMD3<Float>) {
        placementTransform.columns.3 += SIMD4(delta, 0)
        for index in particles.indices {
            particles[index].position += delta
        }
    }

    /// Moves the emitter to `placement`. A world-space system's particles stay where
    /// they were born, so only new ones start from the new place; a local-space
    /// system's particles move and turn with it.
    public mutating func move(to placement: float4x4) {
        move(to: placement, nodeDeltas: nodeDeltas)
    }

    /// Moves the emitter to `placement` with the model's moved nodes, so a system below a
    /// moved node emits where that node is now, and the inherit object's speed is known.
    public mutating func move(to placement: float4x4, nodeDeltas: [String: float4x4]) {
        self.nodeDeltas = nodeDeltas
        // The model placement, before the system's own node change.
        let model = placement
        moveEmitter(to: placement * Self.delta(of: definition.ancestorNodes, in: nodeDeltas))
        trackInheritObject(model: model)
    }

    private mutating func moveEmitter(to placement: float4x4) {
        let change = placement * placementTransform.inverse
        pendingDisplacement += SIMD3(change.columns.3.x, change.columns.3.y, change.columns.3.z)
        placementTransform = placement
        guard !definition.worldSpace else { return }
        for index in particles.indices {
            let position = change * SIMD4(particles[index].position, 1)
            let velocity = change * SIMD4(particles[index].velocity, 0)
            particles[index].position = SIMD3(position.x, position.y, position.z)
            particles[index].velocity = SIMD3(velocity.x, velocity.y, velocity.z)
        }
    }

    public mutating func advance(deltaTime: Float, wind: WindState, emissionScale: Float) {
        let deltaTime = simd_clamp(deltaTime, 0, 0.1)
        guard deltaTime > 0, definition.updatesSimulation else { return }
        emitterVelocity = pendingDisplacement / deltaTime
        pendingDisplacement = .zero
        inheritVelocity = inheritObject == nil ? emitterVelocity
            : pendingInheritDisplacement / deltaTime
        pendingInheritDisplacement = .zero
        activeModifiers = definition.modifiers
            .map { $0.controlled(by: controllers.modifiers, at: elapsed) }
            .filter(\.active).sorted { $0.order < $1.order }
        updateExisting(deltaTime: deltaTime, wind: wind)
        elapsed += deltaTime
        let emitters = currentEmitters
        let controlled = emitters.map(controllerRate(for:))
        if controlled.allSatisfy({ $0 == nil }) {
            emit(deltaTime: deltaTime, scale: max(emissionScale, 0))
        } else {
            emitControlled(
                emitters: emitters, rates: controlled, deltaTime: deltaTime,
                scale: max(emissionScale, 0)
            )
        }
    }

    /// The keyed birth rate of the controller that names this emitter. A file with
    /// one emitter and one unnamed controller pairs them.
    private func controllerRate(for emitter: ParticleEmitter) -> Float? {
        let controllers = controllers.emitters
        let named = controllers.first { $0.modifierName != nil && $0.modifierName == emitter.name }
        let only = controllers.count == 1 && definition.emitters.count == 1 ? controllers
            .first : nil
        return (named ?? only)?.birthRate(at: elapsed)
    }

    private mutating func emitControlled(
        emitters: [ParticleEmitter],
        rates: [Float?],
        deltaTime: Float,
        scale: Float
    ) {
        guard capacity > 0, scale > 0 else { return }
        if controlledAccumulators.count != emitters.count {
            controlledAccumulators = Array(repeating: 0, count: emitters.count)
        }
        let share = fallbackRate(emitters) / Float(emitters.count)
        for (index, emitter) in emitters.enumerated() {
            let rate = rates[index] ?? share
            // A full system does not bank births for later.
            controlledAccumulators[index] = min(
                controlledAccumulators[index] + rate * scale * deltaTime, Float(capacity)
            )
            let births = min(Int(controlledAccumulators[index]), capacity - particles.count)
            guard births > 0 else { continue }
            controlledAccumulators[index] -= Float(births)
            for _ in 0 ..< births {
                particles.append(makeParticle(emitter: emitter))
            }
        }
    }

    private func fallbackRate(_ emitters: [ParticleEmitter]) -> Float {
        let averageLife = max(
            emitters.reduce(0) { $0 + max($1.lifeSpan, 0.1) } / Float(max(emitters.count, 1)),
            0.1
        )
        return simd_clamp(Float(capacity) * 0.25 / averageLife, 6, 60)
    }

    private mutating func updateExisting(deltaTime: Float, wind: WindState) {
        let windVector = SIMD3(wind.direction.x * wind.speed, wind.direction.y * wind.speed, 0)
        let field = ParticleForceField(
            modifiers: activeModifiers,
            modelTransform: placementTransform * definition.worldTransform
        )
        // A local array: an element of `particles` passed inout to a method of `self`
        // made Swift copy the whole simulator and its particles for each particle.
        var live = particles
        particles = []
        var children: [SimulatedParticle] = []
        var dead = RangeSet<Int>()
        for index in live.indices.reversed() {
            live[index].age += deltaTime
            if live[index].age >= live[index].lifetime {
                children += spawned(from: live[index])
                dead.insert(index, within: live)
                continue
            }
            live[index].rotation += live[index].rotationSpeed * deltaTime
            for modifier in activeModifiers {
                apply(modifier, to: &live[index], wind: windVector * deltaTime)
            }
            if !field.move(&live[index], deltaTime: deltaTime, random: &random) {
                dead.insert(index, within: live)
            }
        }
        live.removeSubranges(dead)
        live += children.prefix(max(capacity - live.count, 0))
        particles = live
    }

    /// Applies a modifier that changes a live particle by its age. `wind` is this step's push.
    private func apply(
        _ modifier: ParticleModifier,
        to particle: inout SimulatedParticle,
        wind: SIMD3<Float>
    ) {
        let fraction = particle.age / particle.lifetime
        switch modifier.kind {
        case let .wind(strength):
            particle.velocity += wind * strength
        case let .simpleColour(ramp):
            particle.color = particle.initialColor * ramp.colour(at: fraction)
        case let .scale(scales):
            particle.radius = scaledRadius(
                initial: particle.initialRadius, scales: scales, fraction: fraction
            )
        case let .subTex(subTexture):
            particle.atlasIndex = subTexture.frame(
                at: fraction, drawn: particle.frames,
                frameTotal: definition.subtextureOffsets.count
            )
        default:
            break
        }
    }

    /// The active emitters, with their parameter controllers applied now.
    public var currentEmitters: [ParticleEmitter] {
        definition.emitters
            .map { $0.controlled(by: controllers.modifiers, at: elapsed) }
            .filter(\.active)
    }

    /// Plays `set` from its start; the living particles stay.
    mutating func setControllers(_ set: ParticleControllerSet) {
        controllers = set
        elapsed = 0
        controlledAccumulators.removeAll()
    }

    /// False while the system's `NiVisController` hides it.
    public var isVisible: Bool {
        controllers.visibility?.isVisible(at: elapsed) ?? true
    }

    private mutating func emit(deltaTime: Float, scale: Float) {
        let emitters = currentEmitters
        guard capacity > 0, !emitters.isEmpty, particles.count < capacity, scale > 0 else { return }
        birthAccumulator += fallbackRate(emitters) * scale * deltaTime
        let births = min(Int(birthAccumulator), capacity - particles.count)
        birthAccumulator -= Float(births)
        for _ in 0 ..< births {
            let emitter = emitters[nextEmitter % emitters.count]
            nextEmitter += 1
            particles.append(makeParticle(emitter: emitter))
        }
    }

    var colourRamp: ParticleColourRamp? {
        for modifier in definition.modifiers where modifier.active {
            if case let .simpleColour(ramp) = modifier.kind {
                return ramp
            }
        }
        return nil
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

nonisolated extension ParticleSimulator {
    /// The change of the nearest moved node in `chain`, or identity when none moved.
    static func delta(of chain: [String], in deltas: [String: float4x4]) -> float4x4 {
        guard !deltas.isEmpty else { return matrix_identity_float4x4 }
        for name in chain {
            if let delta = deltas[name] {
                return delta
            }
        }
        return matrix_identity_float4x4
    }

    /// The inherit object of the first inherit velocity modifier that names one.
    private var inheritObject: ParticleInheritVelocity? {
        for modifier in definition.modifiers {
            if case let .inheritVelocity(inherit) = modifier.kind, !inherit.objectNodes.isEmpty {
                return inherit
            }
        }
        return nil
    }

    private mutating func trackInheritObject(model: float4x4) {
        guard let inherit = inheritObject else { return }
        let delta = Self.delta(of: inherit.objectNodes, in: nodeDeltas)
        let point = model * delta * definition.worldTransform * SIMD4(inherit.objectOrigin, 1)
        let position = SIMD3(point.x, point.y, point.z)
        if let last = inheritPosition {
            pendingInheritDisplacement += position - last
        }
        inheritPosition = position
    }
}

/// Layout mirrored by ParticleInstance in ShaderTypes.h.
nonisolated public struct ParticleGPUInstance: Sendable {
    let positionSize: SIMD4<Float>
    let color: SIMD4<Float>
    let uvRect: SIMD4<Float>
    /// The cosine and sine of the billboard turn in x and y.
    let rotation: SIMD4<Float>
}

nonisolated public final class ParticlePlayback: Sendable {
    nonisolated private struct State {
        var simulator: ParticleSimulator
        var simulationTime: Float = 0
        /// Length over width of a rain streak; 0 draws square billboards.
        var streakAspect: Float = 0
    }

    public let name: String
    public let sourcePath: String
    public let texture: any MTLTexture
    public let blendMode: ParticleBlendMode
    /// The system's effect shader. The particle colour always applies, as vertex
    /// colour and alpha, whatever the shader's vertex flags say.
    public let effect: RenderEffectMaterial
    /// The placed reference's `XEMI`, for an effect shader with external emittance.
    public let emittance: EmittanceSource?
    public let instanceBuffer: any MTLBuffer
    /// The meshes each particle of a mesh particle system draws; nil draws billboards.
    public let meshModel: RenderModel?
    /// One `ParticleEffectUniforms` per frame in flight.
    let effectBuffer: any MTLBuffer
    public let capacity: Int
    /// The bolt of a lightning controller; nil for a particle system.
    let lightning: LightningBolt?
    private let seed: UInt64
    /// Advanced on the main actor after the build queue hands the scene over.
    private let state: Mutex<State>

    public var simulator: ParticleSimulator {
        state.withLock { $0.simulator }
    }

    public var liveCount: Int {
        state.withLock { $0.simulator.particles.count }
    }

    public init(
        device: any MTLDevice,
        definition: ParticleSystemDefinition,
        placementTransform: float4x4,
        texture: any MTLTexture,
        effect: RenderEffectMaterial = .plainParticles,
        emittance: EmittanceSource? = nil,
        seed: UInt64,
        sourcePath: String = "(synthetic)",
        meshModel: RenderModel? = nil
    ) throws {
        name = definition.name ?? "Unnamed emitter"
        self.sourcePath = sourcePath
        self.meshModel = meshModel
        self.texture = texture
        self.effect = RenderEffectMaterial.forParticles(effect)
        self.emittance = emittance
        blendMode = ParticleBlendMode(alpha: definition.alphaProperty)
        self.seed = seed
        let simulator = ParticleSimulator(
            definition: definition,
            placementTransform: placementTransform,
            seed: seed
        )
        capacity = definition.lightning == nil ? simulator.capacity : LightningBolt.segmentCapacity
        lightning = definition.lightning.map { LightningBolt(parameters: $0, seed: seed) }
        state = Mutex(State(simulator: simulator))
        let count = max(capacity, 1) * GPUFactory.maxFramesInFlight
        guard
            let buffer = device.makeBuffer(
                length: count * MemoryLayout<ParticleGPUInstance>.stride,
                options: .storageModeShared
            ) else { throw RendererError.bufferAllocationFailed }
        buffer.label = "Particle instances: \(name)"
        instanceBuffer = buffer
        guard
            let uniforms = device.makeBuffer(
                length: Self.effectStride * GPUFactory.maxFramesInFlight,
                options: .storageModeShared
            ) else { throw RendererError.bufferAllocationFailed }
        uniforms.label = "Particle effect: \(name)"
        effectBuffer = uniforms
    }

    static let effectStride = (MemoryLayout<ParticleEffectUniforms>.size + 0xFF) & -0x100

    /// The buffers and textures a draw of this system reads.
    var residencyAllocations: [any MTLAllocation] {
        [instanceBuffer, effectBuffer, texture] + (effect.palette.map { [$0] } ?? [])
    }

    /// Writes the effect uniforms into the slot's range and returns their address.
    func prepareEffect(
        slot: Int, pointLightCount: Int, regions: [UInt32: SIMD3<Float>]
    ) -> UInt64 {
        var uniforms = ParticleEffectUniforms(
            flags: effect.flags,
            pointLightCount: UInt32(pointLightCount),
            baseColorScale: effect.baseColorScale,
            softDepth: effect.softDepth,
            baseColor: effect.baseColor,
            falloff: effect.falloff,
            lighting: SIMD4(effect.lightingInfluence, blendMode.addsLight ? 1 : 0, 0, 0),
            emittance: EmittanceSource.colour(of: emittance, regions: regions)
        )
        let offset = slot * Self.effectStride
        unsafe effectBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<ParticleEffectUniforms>.size)
        return effectBuffer.gpuAddress + UInt64(offset)
    }

    func advance(deltaTime: Float, wind: WindState, emissionScale: Float) {
        state.withLock {
            $0.simulator.advance(deltaTime: deltaTime, wind: wind, emissionScale: emissionScale)
            $0.simulationTime += max(deltaTime, 0)
        }
    }

    func translate(by delta: SIMD3<Float>) {
        state.withLock { $0.simulator.translate(by: delta) }
    }

    public func move(to placement: float4x4) {
        state.withLock { $0.simulator.move(to: placement) }
    }

    /// Moves the emitter with the model's moved nodes, by lowercased node name.
    public func move(to placement: float4x4, nodeDeltas: [String: float4x4]) {
        state.withLock { $0.simulator.move(to: placement, nodeDeltas: nodeDeltas) }
    }

    /// Plays the named NIF sequence's controller keys, as an effect graph asks.
    public func play(sequence name: String) {
        state.withLock { $0.simulator.play(sequence: name) }
    }

    func setSpawnScale(_ scale: PrecipitationScale) {
        state.withLock { $0.simulator.spawnScale = scale }
    }

    /// Draws each particle as a streak along its velocity, `aspect` times as long as wide;
    /// 0 goes back to square billboards.
    public func setStreakAspect(_ aspect: Float) {
        state.withLock { $0.streakAspect = aspect.isFinite ? max(aspect, 0) : 0 }
    }

    /// Seconds played since the last reset; a lightning bolt grows on this clock.
    var playbackTime: Float {
        state.withLock { $0.simulationTime }
    }

    /// True when this system draws ribbon bands instead of square billboards.
    var drawsRibbons: Bool {
        let definition = simulator.definition
        return lightning != nil || definition.isStrip || state.withLock { $0.streakAspect > 0 }
    }

    var streakAspect: Float {
        state.withLock { $0.streakAspect }
    }

    func reset() {
        state.withLock {
            $0.simulator.reset(seed: seed)
            $0.simulationTime = 0
        }
    }

    public func seek(to time: Float, wind: WindState, emissionScale: Float) {
        let target = max(time, 0)
        state.withLock {
            $0.simulator.reset(seed: seed)
            $0.simulationTime = 0
            while $0.simulationTime + 0.05 < target {
                $0.simulator.advance(deltaTime: 0.05, wind: wind, emissionScale: emissionScale)
                $0.simulationTime += 0.05
            }
            let remainder = target - $0.simulationTime
            $0.simulator.advance(deltaTime: remainder, wind: wind, emissionScale: emissionScale)
            $0.simulationTime = target
        }
    }

    /// The emitter's world origin, the point systems are sorted by.
    var origin: SIMD3<Float> {
        let simulator = simulator
        let origin = (simulator.placementTransform * simulator.definition.worldTransform).columns.3
        return SIMD3(origin.x, origin.y, origin.z)
    }
}
