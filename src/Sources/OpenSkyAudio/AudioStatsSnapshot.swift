// What the world audio graph publishes for state reads.

import simd

/// One playing audio source.
nonisolated struct AudioSourceStatsSnapshot: Equatable, Sendable {
    /// VFS path of the playing file.
    let name: String
    let categoryName: String
    /// False for a non-positional source (music or ambience routed to a
    /// category submix): its position and distance are not meaningful.
    let isPositional: Bool
    /// Listener distance in meters (the attenuation model's unit). Zero when
    /// not positional.
    let distanceMeters: Float
    /// Fade multiplier in [0, 1] currently folded into the gain. 1 = not faded.
    let fadeGain: Float
    /// True while a gain ramp is in flight on this source.
    let isFading: Bool
    /// master x category x source x fade gain, before distance attenuation.
    let effectiveGain: Float
    /// How far into its material the source has played, in seconds; nil before its player
    /// node renders. The readout uses it to show a voice line advancing.
    let positionSeconds: Double?
}

/// Published state of the world audio graph, read at 2 Hz by the readout. Only
/// this Equatable value crosses from the engine to the readout.
nonisolated struct AudioStatsSnapshot: Equatable, Sendable {
    let enabled: Bool
    let engineRunning: Bool
    let sources: [AudioSourceStatsSnapshot]
    let sourceCap: Int
    var reverb = ReverbRamp()
}
