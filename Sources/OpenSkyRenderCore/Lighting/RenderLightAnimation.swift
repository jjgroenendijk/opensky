// Flicker and pulse for placed lights. The game's exact curves are not known;
// these are OpenSky shapes driven by the LIGH flicker values
// (docs/formats/lighting.md, docs/engine/interiors.md).

import OpenSkyFormatsESM
import simd

nonisolated public struct RenderLightAnimation: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Smooth random brightness and a small wobble of the position.
        case flicker
        /// A sine wave of brightness.
        case pulse
    }

    public let kind: Kind
    /// Seconds per cycle, after the slow flag.
    public let period: Float
    /// Brightness swing as a fraction of the base colour, 0 to 1.
    public let intensityAmplitude: Float
    /// Largest position offset, in game units.
    public let movementAmplitude: Float
    /// Keeps neighbouring lights out of step.
    public let phase: Float

    public init(
        kind: Kind,
        period: Float,
        intensityAmplitude: Float,
        movementAmplitude: Float,
        phase: Float
    ) {
        self.kind = kind
        self.period = max(period, Self.shortestPeriod)
        self.intensityAmplitude = simd_clamp(intensityAmplitude, 0, 1)
        self.movementAmplitude = max(movementAmplitude, 0)
        self.phase = phase
    }

    /// A shorter period strobes faster than a frame can show.
    public static let shortestPeriod: Float = 0.05

    /// Brightness factor and position offset at `time` seconds.
    public func sample(at time: Float) -> (intensity: Float, offset: SIMD3<Float>) {
        let cycle = time / period + phase
        switch kind {
        case .pulse:
            let wave = sin(cycle * 2 * .pi)
            return (max(1 + intensityAmplitude * wave, 0), .zero)
        case .flicker:
            let intensity = 1 + intensityAmplitude * Self.noise(cycle, seed: 0)
            let offset = SIMD3(
                Self.noise(cycle, seed: 1), Self.noise(cycle, seed: 2), Self.noise(cycle, seed: 3)
            ) * movementAmplitude
            return (max(intensity, 0), offset)
        }
    }

    /// Smooth value noise in -1 to 1: one random value per whole cycle, eased between.
    static func noise(_ value: Float, seed: UInt32) -> Float {
        let lower = value.rounded(.down)
        let fraction = value - lower
        let eased = fraction * fraction * (3 - 2 * fraction)
        let index = Int32(truncatingIfNeeded: Int64(lower))
        let from = lattice(index, seed: seed)
        let to = lattice(index &+ 1, seed: seed)
        return from + (to - from) * eased
    }

    private static func lattice(_ index: Int32, seed: UInt32) -> Float {
        var hash = UInt32(bitPattern: index) &* 0x9E37_79B1 ^ seed &* 0x85EB_CA77
        hash ^= hash >> 15
        hash &*= 0x2C1B_3C6D
        hash ^= hash >> 12
        return Float(hash & 0xFFFF) / 32767.5 - 1
    }
}

nonisolated extension RenderLightAnimation {
    /// Seconds per cycle when the record stores none.
    static let defaultPeriod: Float = 0.5

    /// Nil for a light without a flicker or pulse flag. A slow flag doubles the
    /// period, an OpenSky choice; `reference` puts each placed light out of step.
    public init?(light: LightRecord, reference: UInt32) {
        let flags = light.flags
        let kind: Kind
        if flags.contains(.flicker) || flags.contains(.flickerSlow) {
            kind = .flicker
        } else if flags.contains(.pulse) || flags.contains(.pulseSlow) {
            kind = .pulse
        } else {
            return nil
        }
        let slow = flags.contains(.flickerSlow) || flags.contains(.pulseSlow)
        let flicker = light.flicker
        let period = flicker.period.isFinite && flicker.period > 0
            ? flicker.period : Self.defaultPeriod
        self.init(
            kind: kind,
            period: period * (slow ? 2 : 1),
            intensityAmplitude: flicker.intensityAmplitude.isFinite ? flicker
                .intensityAmplitude : 0,
            movementAmplitude: flicker.movementAmplitude.isFinite ? flicker.movementAmplitude : 0,
            phase: Float(reference % 997) / 997
        )
    }
}
