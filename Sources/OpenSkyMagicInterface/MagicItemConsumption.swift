import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// What one successful consume did.
nonisolated public struct MagicItemConsumeOutcome: Equatable, Sendable {
    public let kind: ActiveEffectSourceKind
    /// Effect entries handed to the runtime — not all of which necessarily
    /// applied; the runtime's tally says which did not and why.
    public let entryCount: Int
    /// The timed effects that became components. Instant effects moved a value
    /// and are not here, by design.
    public let stored: [ActiveEffect]

    public init(
        kind: ActiveEffectSourceKind,
        entryCount: Int,
        stored: [ActiveEffect]
    ) {
        self.kind = kind
        self.entryCount = entryCount
        self.stored = stored
    }
}
