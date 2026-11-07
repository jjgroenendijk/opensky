// Timed fades of placed references on the CPU path. The GPU cull kernel applies the
// same rule (`cullFade` in CullingMotionShaders.metal).

import OpenSkyFormatsCore
import OpenSkyRenderCore
import simd

/// What one cull dispatch needs for the fades.
struct CullFade {
    let distances: ReferenceFadeDistances
    let viewer: SIMD3<Float>
    /// Seconds the camera view advances each fade by.
    let seconds: Float
}

typealias ReferenceFadeTimers = FadeTimers<ReferenceFadeState>

/// The renderer's timed fades: the reference fades and the mesh detail level changes.
struct RendererFadeTimers {
    var references = ReferenceFadeTimers()
    var meshLOD = FadeTimers<MeshLODFade>()
    /// The actor the camera is inside fades out (RendererActorCameraFade.swift).
    var actorCamera = ActorCameraFade()
    /// How much the view centre counts in a "Use Target" depth of field focus.
    var depthOfFieldFocus = DepthOfFieldFocus()

    mutating func advance(seconds: Float) {
        references.advance(seconds: seconds)
        meshLOD.advance(seconds: seconds)
    }
}

/// The CPU path's timed state of each reference, keyed by its form and place, stepped once
/// a frame by the first pass that draws it.
struct FadeTimers<State> {
    struct Key: Hashable {
        let formID: UInt32
        let place: SIMD3<Int32>
    }

    /// Frames an unseen entry is kept before it is dropped.
    static var keepFrames: Int {
        600
    }

    private(set) var tick = 0
    private(set) var seconds: Float = 0
    private var states: [Key: (state: State, tick: Int)] = [:]
    private var gpuTick = 0

    mutating func advance(seconds: Float) {
        tick += 1
        self.seconds = seconds
        if tick % Self.keepFrames == 0 {
            states = states.filter { tick - $0.value.tick < Self.keepFrames }
        }
    }

    /// This frame's seconds for the GPU path, once: a frame encoded again without a
    /// new step must not advance the fades a second time.
    mutating func takeGPUSeconds() -> Float {
        defer { gpuTick = tick }
        return gpuTick == tick ? 0 : seconds
    }

    /// An entry unseen for more than `forgetAfter` frames steps as a new one.
    mutating func state(
        for key: Key,
        forgetAfter: Int? = nil,
        step: (State?, Float) -> State?
    ) -> State? {
        var entry = states[key]
        if let seen = entry, seen.tick == tick {
            return seen.state
        }
        if let seen = entry, let forgetAfter, tick - seen.tick > forgetAfter {
            entry = nil
        }
        guard let next = step(entry?.state, seconds) else { return nil }
        states[key] = (next, tick)
        return next
    }
}

extension DrawInstance {
    /// Actors follow the actor multiplier, references a rigid body moves the item one,
    /// and other cell statics the object one. LOD, terrain, and water never fade.
    var fadeCategory: ReferenceFadeCategory {
        if layer.contains(.actors) {
            return .actor
        }
        guard layer.contains(.statics) else { return .none }
        return referenceFormID != 0 ? .item : .object
    }
}

extension Renderer {
    /// Steps every reference fade by this frame's simulated seconds.
    public func advanceReferenceFades(deltaTime: Float) {
        fadeTimers.advance(seconds: deltaTime)
        advanceViewTimers(seconds: deltaTime)
    }

    /// 0 whole, up to 1 dissolved; nil when `instance` has faded out.
    func distanceFade(of instance: DrawInstance) -> Float? {
        guard referenceFades.isOn, let bounds = instance.bounds else { return 0 }
        let fades = referenceFades
        let viewer = frameInput.view.position
        let center = (bounds.min + bounds.max) * 0.5
        let key = ReferenceFadeTimers.Key(
            formID: instance.referenceFormID, place: SIMD3<Int32>(center.rounded(.down))
        )
        let state = fadeTimers.references.state(for: key) { state, seconds in
            fades.step(
                instance.fadeCategory,
                bounds: ReferenceFadeBounds(lower: bounds.min, upper: bounds.max, viewer: viewer),
                state: state, seconds: seconds
            )
        }
        guard let state else { return 0 }
        return state.dissolve
    }
}
