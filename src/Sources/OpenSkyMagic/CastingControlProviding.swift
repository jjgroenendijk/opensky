// The spellcasting readout's seam: learn, read, ready and cast, without
// `GameViewController`. One snapshot value, so the readout comes from a single
// observation.

import Foundation

/// One observation of the caster runtime.
nonisolated struct CastingControlSnapshot: Equatable, Sendable {
    /// The magic condition functions for the player now, each as `name = value` or
    /// `name: reason`. Here, beside the readied spells they read.
    let conditionLines: [String]
    /// The runes waiting on the ground, then how many went off.
    var runeText = "Runes: none"
    /// The actors the player's summons and reanimations command.
    var commandedText = "Commanded: none"
    /// The casting hands' sounds and art sent, and a release waiting for its event.
    var castingCueText = "Casting cues: 0"

    /// The reading with no runtime attached.
    static let unavailable = CastingControlSnapshot(
        conditionLines: []
    )
}
