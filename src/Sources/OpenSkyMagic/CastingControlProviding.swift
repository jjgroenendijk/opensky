// The spellcasting readout's seam: learn, read, ready and cast, without
// `GameViewController`. One snapshot value, so the readout comes from a single
// observation.

import Foundation

/// One observation of the caster runtime.
nonisolated public struct CastingControlSnapshot: Equatable, Sendable {
    /// The magic condition functions for the player now, each as `name = value` or
    /// `name: reason`. Here, beside the readied spells they read.
    public let conditionLines: [String]
    /// The runes waiting on the ground, then how many went off.
    public var runeText = "Runes: none"
    /// The actors the player's summons and reanimations command.
    public var commandedText = "Commanded: none"
    /// The casting hands' sounds and art sent, and a release waiting for its event.
    public var castingCueText = "Casting cues: 0"

    /// The reading with no runtime attached.
    public static let unavailable = CastingControlSnapshot(
        conditionLines: []
    )

    public init(
        conditionLines: [String]
    ) {
        self.conditionLines = conditionLines
    }
}
