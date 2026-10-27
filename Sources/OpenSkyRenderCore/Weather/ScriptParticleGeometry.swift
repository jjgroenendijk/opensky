// The `SPGD` a script laid over the weather with `ShaderParticleGeometry.Apply`, and its
// fade in or out. The weather's own precipitation stays; the script's adds to it. Pure.
// See docs/engine/papyrus-session-natives.md.

import OpenSkyFormatsESM
import simd

nonisolated public struct ScriptParticleGeometry: Equatable, Sendable {
    public private(set) var record: ShaderParticleGeometry?
    /// How much of the record's precipitation shows, from 0 to 1.
    public private(set) var strength: Float = 0
    private var from: Float = 0
    private var target: Float = 0
    private var duration: Float = 0
    private var elapsed: Float = 0

    public init() {}

    /// Replaces any applied record. A new record fades in from nothing.
    public mutating func apply(_ record: ShaderParticleGeometry, fadeIn seconds: Float) {
        if record != self.record {
            strength = 0
        }
        self.record = record
        start(target: 1, seconds: seconds)
    }

    /// Fades the applied record out, then forgets it.
    public mutating func remove(fadeOut seconds: Float) {
        guard record != nil else { return }
        start(target: 0, seconds: seconds)
    }

    public mutating func advance(_ deltaTime: Float) {
        guard record != nil else { return }
        if deltaTime.isFinite {
            elapsed += max(0, deltaTime)
        }
        let progress = duration > 0 ? simd_clamp(elapsed / duration, 0, 1) : 1
        strength = simd_mix(from, target, progress)
        if progress >= 1, target == 0 {
            record = nil
        }
    }

    /// `state` with this record's precipitation added, at `strength`. `SPGD` type 0 is
    /// rain and type 1 is snow.
    public func adding(to state: PrecipitationState) -> PrecipitationState {
        switch record?.properties?.type {
        case 0:
            PrecipitationState(
                rainIntensity: max(state.rainIntensity, strength),
                snowIntensity: state.snowIntensity
            )
        case 1:
            PrecipitationState(
                rainIntensity: state.rainIntensity,
                snowIntensity: max(state.snowIntensity, strength)
            )
        default:
            state
        }
    }

    private mutating func start(target: Float, seconds: Float) {
        from = strength
        self.target = target
        duration = seconds.isFinite ? max(0, seconds) : 0
        elapsed = 0
        advance(0)
    }
}
