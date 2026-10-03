// What the world audio graph publishes for the World > Audio panel.

import simd

/// One playing audio source as the World > Audio panel shows it.
nonisolated public struct AudioSourceStatsSnapshot: Equatable, Sendable {
    /// VFS path of the playing file.
    public let name: String
    public let categoryName: String
    /// False for a non-positional source (music or ambience routed to a
    /// category submix): its position and distance are not meaningful.
    public let isPositional: Bool
    /// World position in native Skyrim units. Zero when not positional.
    public let worldPosition: SIMD3<Float>
    /// Listener distance in meters (the attenuation model's unit). Zero when
    /// not positional.
    public let distanceMeters: Float
    /// Fade multiplier in [0, 1] currently folded into the gain. 1 = not faded.
    public let fadeGain: Float
    /// True while a gain ramp is in flight on this source.
    public let isFading: Bool
    /// master x category x source x fade gain, before distance attenuation.
    public let effectiveGain: Float
    /// How far into its material the source has played, in seconds; nil before its player
    /// node renders. The panel uses it to show a voice line advancing.
    public let positionSeconds: Double?
    /// The output model that routed the source, nil when its channel count did.
    public var outputModel: String?
    /// The model's distance-curve gain, 1 without a curve.
    public var distanceGain: Float = 1
}

/// Published state of the world audio graph, read at 2 Hz by the panel. Only
/// this Equatable value crosses from the engine to the readout.
nonisolated public struct AudioStatsSnapshot: Equatable, Sendable {
    public let enabled: Bool
    public let engineRunning: Bool
    /// Output device format line, or the failure reason when not running.
    public let outputDescription: String
    public let sources: [AudioSourceStatsSnapshot]
    public let sourceCap: Int
    public var reverb = ReverbRamp()

    /// Reported by providers with no live audio engine.
    public static let empty = AudioStatsSnapshot(
        enabled: false, engineRunning: false, outputDescription: "no engine",
        sources: [], sourceCap: 0
    )
}
