// Shader values that a mesh animates on its own clock: UV scroll, alpha, emissive
// strength and colour, and the effect falloff. Source: NIF shader property controllers
// (docs/formats/nif-controllers.md#shader-property-controllers).

import Foundation
import simd

/// nif.xml `NiTimeController` timing: how seconds map into the key range.
nonisolated public struct ControllerClock: Hashable, Sendable {
    public enum Cycle: UInt16, Hashable, Sendable {
        case loop = 0
        case reverse = 1
        case clamp = 2
    }

    public let cycle: Cycle
    public let frequency: Float
    public let phase: Float
    public let startTime: Float
    public let stopTime: Float

    public init(cycle: Cycle, frequency: Float, phase: Float, startTime: Float, stopTime: Float) {
        self.cycle = cycle
        self.frequency = frequency
        self.phase = phase
        self.startTime = startTime
        self.stopTime = stopTime
    }

    /// Maps a playback time in seconds into the key range.
    public func time(at seconds: Float) -> Float {
        let scaled = seconds * frequency + phase
        let span = stopTime - startTime
        guard span.isFinite, span > 0 else { return scaled }
        let offset = scaled - startTime
        switch cycle {
        case .clamp:
            return simd_clamp(scaled, startTime, stopTime)
        case .loop:
            return startTime + Self.positiveRemainder(offset, span)
        case .reverse:
            let folded = Self.positiveRemainder(offset, span * 2)
            return startTime + (folded <= span ? folded : span * 2 - folded)
        }
    }

    private static func positiveRemainder(_ value: Float, _ divisor: Float) -> Float {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder < 0 ? remainder + divisor : remainder
    }
}

nonisolated public struct MaterialAnimation: Hashable, Sendable {
    /// The material value a track drives.
    public enum Target: UInt8, Hashable, Sendable, CaseIterable {
        case uOffset, vOffset, uScale, vScale
        case alpha
        case emissiveMultiple
        case emissiveColor
        case falloffStartAngle, falloffStopAngle, falloffStartOpacity, falloffStopOpacity
        case glossiness, specularStrength, specularColor
        case environmentScale, refractionStrength
    }

    /// One controller: linear keys on its own clock. A float track keeps its value in `x`.
    public struct Track: Hashable, Sendable {
        public let target: Target
        public let clock: ControllerClock
        public let times: [Float]
        public let values: [SIMD3<Float>]

        public init(
            target: Target,
            clock: ControllerClock,
            times: [Float],
            values: [SIMD3<Float>]
        ) {
            self.target = target
            self.clock = clock
            self.times = times
            self.values = values
        }

        /// The keyed value at `seconds`: the first key before the range, the last after it.
        public func value(at seconds: Float) -> SIMD3<Float>? {
            guard let first = values.first, let last = values.last, times.count == values.count
            else { return nil }
            let time = clock.time(at: seconds)
            guard time > times[0] else { return first }
            guard time < times[times.count - 1] else { return last }
            let upper = times.firstIndex { $0 >= time } ?? times.count - 1
            let span = times[upper] - times[upper - 1]
            let fraction = span > 0 ? (time - times[upper - 1]) / span : 1
            return simd_mix(values[upper - 1], values[upper], SIMD3(repeating: fraction))
        }
    }

    public let tracks: [Track]

    public init(tracks: [Track]) {
        self.tracks = tracks
    }
}
