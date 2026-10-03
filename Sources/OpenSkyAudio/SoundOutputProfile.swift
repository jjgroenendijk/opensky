// What a sound's `SOPM` output model asks of playback: 3D or flat routing, a
// distance curve, and a reverb send. Pure values over the decoded record.
// See docs/formats/sound-output-reverb.md, section "Output models".

import Foundation
import OpenSkyFormatsESM

/// The `ANAM` curve: five gain points spread evenly from the minimum to the
/// maximum distance, in world units.
nonisolated public struct AttenuationCurve: Equatable, Sendable {
    public let minimumDistance: Float
    public let maximumDistance: Float
    /// Gains in 0...1, nearest first.
    public let points: [Float]

    public init(minimumDistance: Float, maximumDistance: Float, points: [Float]) {
        self.minimumDistance = max(minimumDistance.isFinite ? minimumDistance : 0, 0)
        self.maximumDistance = max(
            maximumDistance.isFinite ? maximumDistance : 0, self.minimumDistance
        )
        self.points = points.map { min(max($0.isFinite ? $0 : 0, 0), 1) }
    }

    public init?(_ attenuation: SoundOutputModel.Attenuation?) {
        guard let attenuation, !attenuation.curve.isEmpty else { return nil }
        self.init(
            minimumDistance: attenuation.minimumDistance,
            maximumDistance: attenuation.maximumDistance,
            points: attenuation.curve.map { Float($0) / 100 }
        )
    }

    /// Full gain inside the minimum distance, the last point past the maximum, and
    /// linear between neighbouring points.
    public func gain(atDistance distance: Float) -> Float {
        guard let first = points.first, let last = points.last else { return 1 }
        let distance = distance.isFinite ? distance : maximumDistance
        guard distance > minimumDistance else { return first }
        let span = maximumDistance - minimumDistance
        guard span > 0, distance < maximumDistance, points.count > 1 else { return last }
        let position = (distance - minimumDistance) / span * Float(points.count - 1)
        let lower = min(Int(position), points.count - 2)
        let fraction = position - Float(lower)
        return points[lower] + (points[lower + 1] - points[lower]) * fraction
    }
}

nonisolated public struct OutputModelProfile: Equatable, Sendable {
    public let name: String
    /// Type 0 (HRTF) plays in 3D; type 1 (defined speaker output) plays flat.
    public let routing: AudioRouting
    /// Nil when the model does not set its attenuates-with-distance flag.
    public let attenuation: AttenuationCurve?
    /// The share of the voice sent to the room reverb, 0...1.
    public let reverbSend: Float

    public init(
        name: String,
        routing: AudioRouting,
        attenuation: AttenuationCurve?,
        reverbSend: Float
    ) {
        self.name = name
        self.routing = routing
        self.attenuation = attenuation
        self.reverbSend = min(max(reverbSend.isFinite ? reverbSend : 0, 0), 1)
    }

    /// Nil for a model with no type, which leaves the channel-count rule in charge.
    public init?(model: SoundOutputModel) {
        guard let type = model.type else { return nil }
        let attenuates = (model.flags ?? 0) & 0x01 != 0
        self.init(
            name: model.editorID ?? "\(model.formID)",
            routing: type == 1 ? .nonPositional : .positional,
            attenuation: attenuates ? AttenuationCurve(model.attenuation) : nil,
            reverbSend: Float(model.reverbSendPercent ?? 0) / 100
        )
    }
}

nonisolated public enum AudioRoutingDecision {
    /// The output model's type when there is one; otherwise mono plays in 3D and
    /// anything wider plays flat.
    public static func routing(profile: OutputModelProfile?, channelCount: Int?) -> AudioRouting {
        if let profile {
            return profile.routing
        }
        return (channelCount ?? 1) > 1 ? .nonPositional : .positional
    }
}
