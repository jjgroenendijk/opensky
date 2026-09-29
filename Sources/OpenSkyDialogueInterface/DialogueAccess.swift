// The seam the dialogue menu reads topics through. `DialogueRuntime` conforms,
// and the composition root hands it over as this protocol.

import OpenSkyFormatsESM
import OpenSkyGameData

/// The topics and greeting a speaker offers the player.
@MainActor
public protocol DialogueAccess {
    /// Plugin-side index every selection reads.
    var dialogue: DialogueStore { get }

    /// The player-facing topics `speaker` offers right now.
    func topics(for speaker: ReferenceKey) -> DialogueSelection

    /// The greeting `speaker` opens with, or nil when none applies.
    func greeting(for speaker: ReferenceKey) -> DialogueTopicOffer?
}
