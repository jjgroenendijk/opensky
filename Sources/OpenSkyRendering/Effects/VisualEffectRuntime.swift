// Live visual effects: an effect-art model and an optional membrane, attached
// to an actor or a point. Each frame the caller supplies where each anchor is;
// the runtime answers which models and membranes to draw. Pure values, so it
// tests without Metal. See docs/rendering/visual-effects.md.

import Foundation
import OpenSkyFormatsESM
import simd

/// What an effect follows.
nonisolated public enum EffectAnchor: Hashable, Sendable {
    case actor(ReferenceKey)
    case point(SIMD3<Float>)
    /// A point on a surface, with the model's up turned to the surface normal.
    case surface(SIMD3<Float>, normal: SIMD3<Float>)
}

/// Why an effect is live, for the readout and for removing one source's effects.
nonisolated public enum VisualEffectCause: String, Equatable, Sendable, CaseIterable {
    case race, spellHit, explosion, impact, script, debug
}

/// The resolved look of one `RFCT` (or one `EFSH` alone).
nonisolated public struct VisualEffectSpec: Equatable, Sendable {
    public let name: String
    /// The effect art's model path, nil when the effect is a membrane only.
    public let artModel: String?
    public let membrane: MembraneLook?
    /// `RFCT` flag 0x02: the art rides the camera instead of its target.
    public let attachesToCamera: Bool
    /// `RFCT` flag 0x04: a camera effect turns with the view, not only moves with it.
    public let inheritsRotation: Bool

    public init(
        name: String, artModel: String?, membrane: MembraneLook?,
        attachesToCamera: Bool = false, inheritsRotation: Bool = false
    ) {
        self.name = name
        self.artModel = artModel
        self.membrane = membrane
        self.attachesToCamera = attachesToCamera
        self.inheritsRotation = inheritsRotation
    }

    /// Whether drawing it would show anything.
    public var isVisible: Bool {
        artModel != nil || membrane != nil
    }
}

nonisolated public struct VisualEffectInstance: Equatable, Sendable {
    public let id: Int
    public let spec: VisualEffectSpec
    public let anchor: EffectAnchor
    public let cause: VisualEffectCause
    /// Seconds it lives, or nil for one that stays until it is detached.
    public let duration: Float?
    public internal(set) var elapsed: Float = 0

    public var isExpired: Bool {
        duration.map { elapsed >= $0 } ?? false
    }
}

/// One effect model to draw this frame.
nonisolated public struct VisualEffectModel: Equatable, Sendable {
    public let path: String
    public let transform: float4x4
    /// The live effect it draws for, so its particle systems persist across frames.
    public let instanceID: Int?

    public init(path: String, transform: float4x4, instanceID: Int? = nil) {
        self.path = path
        self.transform = transform
        self.instanceID = instanceID
    }
}

nonisolated public struct VisualEffectRuntime: Sendable {
    /// At most this many effects live at once; the oldest timed one goes first.
    public static let limit = 32

    public private(set) var instances: [VisualEffectInstance] = []
    public private(set) var attachedTotal = 0
    private var nextID = 1

    public init() {}

    /// Attaches `spec` to `anchor`. A lasting effect already on the same anchor is kept
    /// rather than doubled. Returns the instance id, or nil for an invisible spec.
    @discardableResult
    public mutating func attach(
        _ spec: VisualEffectSpec,
        to anchor: EffectAnchor,
        cause: VisualEffectCause,
        duration: Float?
    ) -> Int? {
        guard spec.isVisible else { return nil }
        if
            duration == nil,
            let existing = instances.first(where: {
                $0.duration == nil && $0.anchor == anchor && $0.spec == spec
            })
        {
            return existing.id
        }
        let id = nextID
        nextID += 1
        attachedTotal += 1
        let clamped = duration.map { $0.isFinite ? max($0, 0) : 0 }
        instances.append(VisualEffectInstance(
            id: id, spec: spec, anchor: anchor, cause: cause, duration: clamped
        ))
        if instances.count > Self.limit {
            let victim = instances.firstIndex { $0.duration != nil } ?? 0
            instances.remove(at: victim)
        }
        return id
    }

    /// Removes every effect on `anchor`, for an actor that unloads or dies.
    public mutating func detachAll(from anchor: EffectAnchor) {
        instances.removeAll { $0.anchor == anchor }
    }

    /// Removes the effects of `spec` on `anchor`. Returns how many went.
    @discardableResult
    public mutating func detach(_ spec: VisualEffectSpec, from anchor: EffectAnchor) -> Int {
        let before = instances.count
        instances.removeAll { $0.spec == spec && $0.anchor == anchor }
        return before - instances.count
    }

    public mutating func removeAll(cause: VisualEffectCause? = nil) {
        instances.removeAll { cause == nil || $0.cause == cause }
    }

    /// Ages every effect and drops the expired. Returns the ids that expired.
    @discardableResult
    public mutating func advance(_ seconds: Float) -> [Int] {
        let step = seconds.isFinite ? max(seconds, 0) : 0
        for index in instances.indices {
            instances[index].elapsed += step
        }
        let expired = instances.filter(\.isExpired).map(\.id)
        instances.removeAll(where: \.isExpired)
        return expired
    }

    /// The models to draw, at the transform `locate` gives each anchor, or at `camera`
    /// for a camera effect. An anchor `locate` cannot place (an unloaded actor) draws
    /// nothing this frame.
    public func models(
        camera: CameraPose? = nil, locate: (EffectAnchor) -> float4x4?
    ) -> [VisualEffectModel] {
        instances.compactMap { instance in
            let spec = instance.spec
            let onCamera = spec.attachesToCamera
                ? camera.map { $0.placement(turning: spec.inheritsRotation) } : nil
            guard let path = spec.artModel, let transform = onCamera ?? locate(instance.anchor)
            else { return nil }
            return VisualEffectModel(path: path, transform: transform, instanceID: instance.id)
        }
    }

    /// Where the view is, for an effect that rides the camera.
    public struct CameraPose: Equatable, Sendable {
        public let eye: SIMD3<Float>
        public let target: SIMD3<Float>

        public init(eye: SIMD3<Float>, target: SIMD3<Float>) {
            self.eye = eye
            self.target = target
        }

        /// At the eye. Turning puts the model's +Y along the view and +Z up, the
        /// way an effect mesh is authored; otherwise it keeps the world axes.
        func placement(turning: Bool) -> float4x4 {
            var matrix = matrix_identity_float4x4
            let look = target - eye
            let worldUp = SIMD3<Float>(0, 0, 1)
            let side = simd_cross(look, worldUp)
            if turning, simd_length_squared(look) > 1e-8, simd_length_squared(side) > 1e-8 {
                let forward = simd_normalize(look)
                let right = simd_normalize(side)
                let up = simd_cross(right, forward)
                matrix.columns.0 = SIMD4(right, 0)
                matrix.columns.1 = SIMD4(forward, 0)
                matrix.columns.2 = SIMD4(up, 0)
            }
            matrix.columns.3 = SIMD4(eye, 1)
            return matrix
        }
    }

    /// The membranes to draw, on the target `target` names for each anchor.
    public func membranes(target: (EffectAnchor) -> MembraneTarget?) -> [MembraneDraw] {
        instances.compactMap { instance in
            guard let look = instance.spec.membrane, let on = target(instance.anchor)
            else { return nil }
            return look.draw(on: on, at: instance.elapsed)
        }
    }
}
