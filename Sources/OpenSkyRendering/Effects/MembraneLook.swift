// The membrane half of an `EFSH` effect shader, reduced to what the additive
// overlay draws: a fill color, an edge color, and their alpha envelopes.
// See docs/formats/effect-shaders.md and docs/rendering/visual-effects.md.

import Foundation
import OpenSkyFormatsESM
import simd

/// One alpha curve: ramp up, hold, ramp down to a persistent level, plus a pulse.
nonisolated public struct MembraneAlphaEnvelope: Equatable, Sendable {
    public var fadeIn: Float = 0
    public var full: Float = 0
    public var fadeOut: Float = 0
    public var fullRatio: Float = 1
    public var persistentRatio: Float = 0
    public var pulseAmplitude: Float = 0
    public var pulseFrequency: Float = 0

    public init() {}

    /// Seconds until the curve settles at its persistent level.
    public var settleTime: Float {
        fadeIn + full + fadeOut
    }

    /// Alpha in 0...1 at `time` seconds since the membrane started.
    public func alpha(at time: Float) -> Float {
        let time = max(0, time.isFinite ? time : 0)
        let base: Float = if time < fadeIn {
            fullRatio * time / fadeIn
        } else if time < fadeIn + full {
            fullRatio
        } else if time < settleTime, fadeOut > 0 {
            fullRatio + (persistentRatio - fullRatio) * (time - fadeIn - full) / fadeOut
        } else {
            persistentRatio
        }
        let pulse = pulseAmplitude * sin(2 * Float.pi * pulseFrequency * time)
        return min(max(base + pulse, 0), 1)
    }
}

nonisolated public struct MembraneLook: Equatable, Sendable {
    /// Linear RGB.
    public var fillColor: SIMD3<Float>
    public var edgeColor: SIMD3<Float>
    public var edgeFalloff: Float
    public var fill: MembraneAlphaEnvelope
    public var edge: MembraneAlphaEnvelope

    /// Nil when the shader sets the no-membrane flag (0x01) or names no fill color.
    public init?(shader: EffectShader) {
        if let flags = shader.flags, flags & 0x01 != 0 {
            return nil
        }
        guard let fill = Self.color(shader, .fillColorKey1) else { return nil }
        fillColor = fill
        edgeColor = Self.color(shader, .edgeColor) ?? .zero
        edgeFalloff = Self.float(shader, .edgeFalloff) ?? 1
        self.fill = Self.envelope(shader, fill: true)
        edge = Self.envelope(shader, fill: false)
    }

    public init(
        fillColor: SIMD3<Float>,
        edgeColor: SIMD3<Float> = .zero,
        edgeFalloff: Float = 1,
        fill: MembraneAlphaEnvelope = MembraneAlphaEnvelope(),
        edge: MembraneAlphaEnvelope = MembraneAlphaEnvelope()
    ) {
        self.fillColor = fillColor
        self.edgeColor = edgeColor
        self.edgeFalloff = edgeFalloff
        self.fill = fill
        self.edge = edge
    }

    /// Seconds a hit-shader membrane plays: until both curves settle, at least half a second.
    public var hitDuration: Float {
        max(fill.settleTime, edge.settleTime, 0.5)
    }

    /// The overlay one frame draws, `time` seconds after the membrane started.
    public func draw(on target: MembraneTarget, at time: Float) -> MembraneDraw {
        MembraneDraw(
            target: target,
            fill: fillColor * fill.alpha(at: time),
            edge: edgeColor * edge.alpha(at: time),
            edgeFalloff: edgeFalloff
        )
    }

    private static func envelope(_ shader: EffectShader, fill: Bool) -> MembraneAlphaEnvelope {
        var envelope = MembraneAlphaEnvelope()
        envelope.fadeIn = float(shader, fill ? .fillAlphaFadeInTime : .edgeAlphaFadeInTime) ?? 0
        envelope.full = float(shader, fill ? .fillFullAlphaTime : .edgeFullAlphaTime) ?? 0
        envelope.fadeOut = float(shader, fill ? .fillAlphaFadeOutTime : .edgeAlphaFadeOutTime) ?? 0
        envelope.fullRatio = float(shader, fill ? .fillFullAlphaRatio : .edgeFullAlphaRatio) ?? 1
        envelope.persistentRatio = float(
            shader, fill ? .fillPersistentAlphaRatio : .edgePersistentAlphaRatio
        ) ?? 0
        envelope.pulseAmplitude = float(
            shader, fill ? .fillAlphaPulseAmplitude : .edgeAlphaPulseAmplitude
        ) ?? 0
        envelope.pulseFrequency = float(
            shader, fill ? .fillAlphaPulseFrequency : .edgeAlphaPulseFrequency
        ) ?? 0
        return envelope
    }

    /// A finite, non-negative member, so a corrupt float cannot poison the curve.
    private static func float(_ shader: EffectShader, _ member: EffectShaderMember) -> Float? {
        guard case let .float(value) = shader.value(member), value.isFinite else { return nil }
        return max(value, 0)
    }

    /// The record stores sRGB bytes; the overlay blends in linear space.
    private static func color(
        _ shader: EffectShader,
        _ member: EffectShaderMember
    ) -> SIMD3<Float>? {
        guard case let .color(bytes) = shader.value(member) else { return nil }
        let srgb = SIMD3<Float>(Float(bytes.x), Float(bytes.y), Float(bytes.z)) / 255
        return SIMD3(pow(srgb.x, 2.2), pow(srgb.y, 2.2), pow(srgb.z, 2.2))
    }
}
