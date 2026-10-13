// Every `NiControllerSequence` of a NIF with its keys, for meshes the engine plays
// by sequence name, such as the perk sky's stars and lines.
// Layout: docs/formats/nif-sequences.md.

import Foundation
import OpenSkyFormatsCore
import simd

/// One named animation of a mesh: its timing, its text keys, and its tracks.
nonisolated public struct NIFSequence: Equatable, Sendable {
    public let name: String
    public let timing: ControllerTiming
    /// `NiTextKeyExtraData`: names at sequence times, such as `start` and `end`.
    public let textKeys: [NIFKey<String>]
    public let tracks: [NIFSequenceTrack]

    public init(
        name: String, timing: ControllerTiming, textKeys: [NIFKey<String>],
        tracks: [NIFSequenceTrack]
    ) {
        self.name = name
        self.timing = timing
        self.textKeys = textKeys
        self.tracks = tracks
    }

    /// Seconds from start to stop at the sequence's frequency.
    public var duration: Float {
        (timing.stopTime - timing.startTime) / max(timing.frequency, .ulpOfOne)
    }

    /// The key time `seconds` after the sequence started: a loop wraps, a clamp
    /// holds its last key.
    public func keyTime(after seconds: Float) -> Float {
        let span = timing.stopTime - timing.startTime
        let advanced = max(seconds, 0) * timing.frequency
        guard span > 0 else { return timing.startTime }
        switch timing.cycle {
        case .loop: return timing.startTime + advanced.truncatingRemainder(dividingBy: span)
        case .reverse:
            let phase = advanced.truncatingRemainder(dividingBy: 2 * span)
            return timing.startTime + (phase <= span ? phase : 2 * span - phase)
        case .clamp: return timing.startTime + min(advanced, span)
        }
    }

    /// True once a clamped sequence has reached its stop time.
    public func isFinished(after seconds: Float) -> Bool {
        timing.cycle == .clamp && max(seconds, 0) * timing.frequency
            >= timing.stopTime - timing.startTime
    }
}

/// One controlled value of a sequence.
nonisolated public struct NIFSequenceTrack: Equatable, Sendable {
    public enum Target: Equatable, Sendable {
        /// A scene graph object by name.
        case node(String)
        /// A shader property by block index; it colours every shape that uses it.
        case shaderProperty(block: Int)
    }

    public enum Channel: Equatable, Sendable {
        case transform(NIFTransformChannel)
        /// nif.xml `EffectShaderControlledVariable` or `LightingShaderControlledFloat`.
        case shaderFloat(variable: UInt32, keys: [NIFKey<Float>])
        /// nif.xml `EffectShaderControlledColor` or `LightingShaderControlledColor`.
        case shaderColor(variable: UInt32, keys: [NIFKey<SIMD3<Float>>])
        case visibility([NIFKey<Bool>])
    }

    public let target: Target
    public let channel: Channel

    public init(target: Target, channel: Channel) {
        self.target = target
        self.channel = channel
    }
}

/// An `NiTransformInterpolator`: a pose, where each part may be unset, and keys.
nonisolated public struct NIFTransformChannel: Equatable, Sendable {
    public let translation: SIMD3<Float>?
    public let rotation: simd_quatf?
    public let scale: Float?
    public let keys: NIFTransformData?

    public init(
        translation: SIMD3<Float>?, rotation: simd_quatf?, scale: Float?,
        keys: NIFTransformData?
    ) {
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
        self.keys = keys
    }

    public func translation(at time: Float) -> SIMD3<Float>? {
        NIFKeySampler.vector(keys?.translations ?? [], at: time) ?? translation
    }

    public func rotation(at time: Float) -> simd_quatf? {
        keys?.rotation(at: time) ?? rotation
    }

    public func scale(at time: Float) -> Float? {
        NIFKeySampler.float(keys?.scales ?? [], at: time) ?? scale
    }
}

nonisolated extension NIFFile {
    /// Every controller sequence in the file, in block order.
    public func sequences() throws -> [NIFSequence] {
        try blocks.indices
            .filter { blocks[$0].typeName == NIFControllerSequenceDecoder.sequenceType }
            .map { try NIFSequenceDecoder(file: self).sequence(blocks[$0]) }
    }
}
