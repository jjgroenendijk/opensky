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

/// A controller that animates one parameter of the emitter or modifier it names.
nonisolated public struct ParticleModifierController: Equatable, Sendable {
    public enum Parameter: String, CaseIterable, Sendable {
        case active = "NiPSysModifierActiveCtlr"
        case emitterSpeed = "NiPSysEmitterSpeedCtlr"
        case gravityStrength = "NiPSysGravityStrengthCtlr"
        case initialRadius = "NiPSysEmitterInitialRadiusCtlr"
        case lifeSpan = "NiPSysEmitterLifeSpanCtlr"
        case declination = "NiPSysEmitterDeclinationCtlr"
        case planarAngle = "NiPSysEmitterPlanarAngleCtlr"
        case initialRotationSpeed = "NiPSysInitialRotSpeedCtlr"
    }

    public let parameter: Parameter
    public let modifierName: String?
    public let timing: ControllerTiming
    /// Empty for `active`, which uses `boolKeys`.
    public let floatKeys: [NIFKey<Float>]
    public let boolKeys: [NIFKey<Bool>]

    public init(
        parameter: Parameter, modifierName: String?, timing: ControllerTiming,
        floatKeys: [NIFKey<Float>] = [], boolKeys: [NIFKey<Bool>] = []
    ) {
        self.parameter = parameter
        self.modifierName = modifierName
        self.timing = timing
        self.floatKeys = floatKeys
        self.boolKeys = boolKeys
    }

    /// The keyed value at `seconds` of playback; nil without keys.
    public func value(at seconds: Float) -> Float? {
        NIFKeySampler.float(floatKeys, at: timing.controllerTime(at: seconds))
    }

    /// The keyed on or off state at `seconds`; nil without keys.
    public func isActive(at seconds: Float) -> Bool? {
        NIFKeySampler.step(boolKeys, at: timing.controllerTime(at: seconds))
    }
}

/// An `NiVisController` on a particle system: shown or hidden over time.
nonisolated public struct ParticleVisibilityTrack: Equatable, Sendable {
    public let timing: ControllerTiming
    public let keys: [NIFKey<Bool>]

    public init(timing: ControllerTiming, keys: [NIFKey<Bool>]) {
        self.timing = timing
        self.keys = keys
    }

    public func isVisible(at seconds: Float) -> Bool {
        NIFKeySampler.step(keys, at: timing.controllerTime(at: seconds)) ?? true
    }
}

/// Every controller on a particle system's controller chain.
nonisolated public struct ParticleControllerSet: Equatable, Sendable {
    public var emitters: [ParticleEmitterController]
    public var modifiers: [ParticleModifierController]
    public var visibility: ParticleVisibilityTrack?
    public var updatesSimulation: Bool

    public init(
        emitters: [ParticleEmitterController] = [],
        modifiers: [ParticleModifierController] = [],
        visibility: ParticleVisibilityTrack? = nil,
        updatesSimulation: Bool = true
    ) {
        self.emitters = emitters
        self.modifiers = modifiers
        self.visibility = visibility
        self.updatesSimulation = updatesSimulation
    }
}

nonisolated extension ParticleEmitter {
    /// The emitter with each controller that names it applied at `seconds`.
    public func controlled(
        by controllers: [ParticleModifierController],
        at seconds: Float
    ) -> ParticleEmitter {
        var values = SIMD8<Float>(speed, initialRadius, lifeSpan, declination, planarAngle, 0, 0, 0)
        var isActive = active
        for controller in controllers where controller.modifierName == name {
            switch controller.parameter {
            case .active: isActive = controller.isActive(at: seconds) ?? isActive
            case .emitterSpeed: values[0] = controller.value(at: seconds) ?? values[0]
            case .initialRadius: values[1] = controller.value(at: seconds) ?? values[1]
            case .lifeSpan: values[2] = controller.value(at: seconds) ?? values[2]
            case .declination: values[3] = controller.value(at: seconds) ?? values[3]
            case .planarAngle: values[4] = controller.value(at: seconds) ?? values[4]
            case .gravityStrength, .initialRotationSpeed: break
            }
        }
        return ParticleEmitter(
            name: name, order: order, active: isActive, speed: values[0],
            speedVariation: speedVariation, declination: values[3],
            declinationVariation: declinationVariation, planarAngle: values[4],
            planarAngleVariation: planarAngleVariation, initialColor: initialColor,
            initialRadius: values[1], radiusVariation: radiusVariation,
            lifeSpan: values[2], lifeSpanVariation: lifeSpanVariation, shape: shape
        )
    }
}

nonisolated extension ParticleModifier {
    /// The modifier with each controller that names it applied at `seconds`.
    public func controlled(
        by controllers: [ParticleModifierController],
        at seconds: Float
    ) -> ParticleModifier {
        var isActive = active
        var controlledKind = kind
        for controller in controllers where controller.modifierName == name {
            switch (controller.parameter, controlledKind) {
            case (.active, _):
                isActive = controller.isActive(at: seconds) ?? isActive
            case var (.gravityStrength, .gravity(gravity)):
                gravity.strength = controller.value(at: seconds) ?? gravity.strength
                controlledKind = .gravity(gravity)
            case var (.initialRotationSpeed, .rotation(rotation)):
                rotation.speed = controller.value(at: seconds) ?? rotation.speed
                controlledKind = .rotation(rotation)
            default:
                break
            }
        }
        return ParticleModifier(name: name, order: order, active: isActive, kind: controlledKind)
    }
}
