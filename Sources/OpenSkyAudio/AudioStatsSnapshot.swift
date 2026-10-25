// What the world audio graph publishes for state reads.

import simd

/// One playing audio source.
nonisolated public struct AudioSourceStatsSnapshot: Equatable, Sendable {
    /// VFS path of the playing file.
    public let name: String
    public let categoryName: String
    /// False for a non-positional source (music or ambience routed to a
    /// category submix): its position and distance are not meaningful.
    public let isPositional: Bool
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
    /// node renders. The readout uses it to show a voice line advancing.
    public let positionSeconds: Double?
}

/// Published state of the world audio graph, read at 2 Hz by the readout. Only
/// this Equatable value crosses from the engine to the readout.
nonisolated public struct AudioStatsSnapshot: Equatable, Sendable {
    public let enabled: Bool
    public let engineRunning: Bool
    public let sources: [AudioSourceStatsSnapshot]
    public let sourceCap: Int
    public var reverb = ReverbRamp()
}
