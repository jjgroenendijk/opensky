// `NiPSysEmitterCtlr`: the birth rate and the on/off track of one emitter over
// the controller's time. Layout and timing: docs/formats/nif-particles.md.

import Foundation
import simd

/// nif.xml `CycleType`: what happens when time passes the controller's stop time.
nonisolated public enum ControllerCycle: UInt16, Equatable, Sendable {
    case loop = 0
    case reverse = 1
    case clamp = 2
}

/// nif.xml `NiTimeController` timing.
nonisolated public struct ControllerTiming: Equatable, Sendable {
    public let cycle: ControllerCycle
    public let frequency: Float
    public let phase: Float
    public let startTime: Float
    public let stopTime: Float

    public init(
        cycle: ControllerCycle,
        frequency: Float,
        phase: Float,
        startTime: Float,
        stopTime: Float
    ) {
        self.cycle = cycle
        self.frequency = frequency
        self.phase = phase
        self.startTime = startTime
        self.stopTime = stopTime
    }

    /// Maps a playback time in seconds into the key range.
    public func controllerTime(at seconds: Float) -> Float {
        let scaled = seconds * frequency + phase
        let span = stopTime - startTime
        guard span.isFinite, span > 0 else { return scaled }
        let offset = scaled - startTime
        switch cycle {
        case .clamp:
            return simd_clamp(scaled, startTime, stopTime)
        case .loop:
            return startTime + positiveRemainder(offset, span)
        case .reverse:
            let folded = positiveRemainder(offset, span * 2)
            return startTime + (folded <= span ? folded : span * 2 - folded)
        }
    }

    private func positiveRemainder(_ value: Float, _ divisor: Float) -> Float {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder < 0 ? remainder + divisor : remainder
    }
}

nonisolated public struct ParticleEmitterController: Equatable, Sendable {
    /// The emitter this controller drives, matched by modifier name.
    public let modifierName: String?
    public let timing: ControllerTiming
    /// Births per second: keys from `NiFloatData`, or one pose value.
    public let birthRate: [NIFKey<Float>]
    /// Emitter on or off: keys from `NiBoolData`, or one pose value. Empty means on.
    public let active: [NIFKey<Bool>]

    public init(
        modifierName: String?,
        timing: ControllerTiming,
        birthRate: [NIFKey<Float>],
        active: [NIFKey<Bool>]
    ) {
        self.modifierName = modifierName
        self.timing = timing
        self.birthRate = birthRate
        self.active = active
    }

    /// Births per second at `seconds` of playback; zero while the emitter is off.
    /// Nil when the controller has no birth rate, so the caller keeps its own rate.
    public func birthRate(at seconds: Float) -> Float? {
        guard let first = birthRate.first, let last = birthRate.last else { return nil }
        let time = timing.controllerTime(at: seconds)
        guard isActive(at: time) else { return 0 }
        guard time > first.time else { return max(first.value, 0) }
        guard time < last.time else { return max(last.value, 0) }
        let upper = birthRate.firstIndex { $0.time >= time } ?? birthRate.count - 1
        let lower = birthRate[upper - 1]
        let span = birthRate[upper].time - lower.time
        let fraction = span > 0 ? (time - lower.time) / span : 1
        return max(lower.value + (birthRate[upper].value - lower.value) * fraction, 0)
    }

    /// Bool keys step: each holds until the next key.
    private func isActive(at time: Float) -> Bool {
        guard let first = active.first else { return true }
        return active.last { $0.time <= time }?.value ?? first.value
    }
}
