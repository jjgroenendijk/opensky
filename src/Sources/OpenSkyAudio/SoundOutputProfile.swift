// What a sound's `SOPM` output model asks of playback: 3D or flat routing, a
// distance curve, and a reverb send. Pure values over the decoded record.
// See docs/formats/sound-output-reverb.md, section "Output models".

import Foundation
public import OpenSkyFormatsESM

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
    /// Type 0 (HRTF) plays in 3D; type 1 (defined speaker output) plays flat.
    public let routing: AudioRouting
    /// Nil when the model does not set its attenuates-with-distance flag.
    public let attenuation: AttenuationCurve?
    /// The share of the voice sent to the room reverb, 0...1.
    public let reverbSend: Float
    /// A speaker output model's matrix folded to stereo; nil plays at full gain, centred.
    public let speakers: SpeakerFold?
    /// `NAM1` flag 0x02: the descriptor's rumble send reaches the controller.
    public let allowsRumble: Bool

    public init(
        routing: AudioRouting,
        attenuation: AttenuationCurve?,
        reverbSend: Float,
        speakers: SpeakerFold? = nil,
        allowsRumble: Bool = false
    ) {
        self.allowsRumble = allowsRumble
        self.routing = routing
        self.attenuation = attenuation
        self.reverbSend = min(max(reverbSend.isFinite ? reverbSend : 0, 0), 1)
        self.speakers = speakers
    }

    /// Nil for a model with no type, which leaves the channel-count rule in charge.
    public init?(model: SoundOutputModel) {
        guard let type = model.type else { return nil }
        let attenuates = (model.flags ?? 0) & 0x01 != 0
        self.init(
            routing: type == 1 ? .nonPositional : .positional,
            attenuation: attenuates ? AttenuationCurve(model.attenuation) : nil,
            reverbSend: Float(model.reverbSendPercent ?? 0) / 100,
            speakers: type == 1 ? SpeakerFold(matrix: model.channelMatrix) : nil,
            allowsRumble: (model.flags ?? 0) & 0x02 != 0
        )
    }
}

/// A `SOPM` `ONAM` speaker matrix played on two speakers. The centre and the four
/// surrounds fold into the front pair at -3 dB each; the LFE is dropped
/// (docs/formats/sound-output-reverb.md#output-model-mapping).
nonisolated public struct SpeakerFold: Equatable, Sendable {
    /// The louder ear's level, 0...1.
    public let gain: Float
    /// -1 is all left, 1 all right.
    public let pan: Float

    /// Nil for a matrix that is not 3 rows of 8 levels. The rows are mono, stereo left,
    /// and stereo right. A mono file reads the first row, a stereo file the other two.
    public init?(matrix: [[UInt8]], channelCount: Int = 1) {
        guard matrix.count == 3, matrix.allSatisfy({ $0.count == 8 }) else { return nil }
        let rows = channelCount > 1 ? [matrix[1], matrix[2]] : [matrix[0]]
        var left: Float = 0
        var right: Float = 0
        for row in rows {
            let level = row.map { Float($0) / 100 }
            let half = Float(0.5).squareRoot()
            left += level[0] + half * (level[2] + level[4] + level[6])
            right += level[1] + half * (level[2] + level[5] + level[7])
        }
        left = min(left / Float(rows.count), 1)
        right = min(right / Float(rows.count), 1)
        let louder = max(left, right)
        gain = louder
        pan = louder > 0 ? (right - left) / louder : 0
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
