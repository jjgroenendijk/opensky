// What the player knows of shouts. `Game.TeachWord`, `Game.UnlockWord`,
// `Actor.AddShout`, and `Actor.EquipShout` keep it in the script state; the app reads
// it from there, so a script and the readout change one record. See docs/engine/shouts.md.

import OpenSkyFormatsESM

nonisolated public struct ShoutKnowledge: Equatable, Sendable {
    /// Shouts `AddShout` gave.
    public var shouts: Set<ReferenceKey>
    public var equipped: ReferenceKey?
    public var knownWords: Set<ReferenceKey>
    public var unlockedWords: Set<ReferenceKey>

    public init(
        shouts: Set<ReferenceKey> = [],
        equipped: ReferenceKey? = nil,
        knownWords: Set<ReferenceKey> = [],
        unlockedWords: Set<ReferenceKey> = []
    ) {
        self.shouts = shouts
        self.equipped = equipped
        self.knownWords = knownWords
        self.unlockedWords = unlockedWords
    }
}

nonisolated public enum ShoutKnowledgeChange: Equatable, Sendable {
    case addShout(ReferenceKey)
    case equip(ReferenceKey)
    case teachWord(ReferenceKey)
    case unlockWord(ReferenceKey)
}
