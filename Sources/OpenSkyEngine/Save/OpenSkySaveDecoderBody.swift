// The decoder's parsed-chunk bag (issue #508), split out of
// `OpenSkySaveDecoder.swift` when that type reached its strict length cap.
//
// The split is along a real seam rather than an arbitrary line count. The parent
// file is the *routing*: read a chunk, dispatch on its tag, merge the results
// into one snapshot. This file is the *shape* of what those chunks decode into,
// and — more usefully — the record of what an absent chunk means, which is the
// whole compatibility contract of an additive container. A reader adding a chunk
// needs this file; a reader changing how a chunk is found needs the other one.
//
// Declared as a nested type in an extension so every reference in the parent
// file stays `Body`, and `internal` rather than `private` only because a
// `private` nested type is invisible across files.

import Foundation
import OpenSkyWorldState

nonisolated extension OpenSkySaveDecoder {
    /// Parsed chunk payloads, with the defaults an absent chunk implies.
    public struct Body: Sendable {
        public var entries: [WorldStateSnapshotEntry] = []
        /// Absent `GVAR` chunk means no global was overridden, which is also
        /// what a save written before that chunk existed means.
        public var globals: [WorldStateGlobalSnapshotEntry] = []
        /// Matches `GeneratedReferenceAllocator`'s starting position, so a
        /// file with no `GALC` chunk restores an allocator that has handed
        /// out nothing.
        public var nextGeneratedSequence: UInt64 = 1
        /// Absent `CLOK` chunk (issue #164) means the vanilla-start clock,
        /// which is also what a save written before that chunk existed means.
        public var clock: GameClock?
        /// Absent `PSCR` chunk (issue #171) means no script instance state was
        /// saved, so every script starts from its compiled defaults — which is
        /// also what a save written before that chunk existed means.
        public var scripts: [PapyrusInstanceState] = []
        /// Absent `PTMR` chunk (issue #277) means no update timer was pending,
        /// which is also what a save written before that chunk existed means.
        public var timers: [PapyrusTimerState] = []
        /// Absent `INVN` chunk (issue #176) means no owner's inventory deviated
        /// from plugin data, so every container and actor re-derives its
        /// contents from its records — which is also what a save written before
        /// that chunk existed means.
        public var inventories: [SaveInventoryEntry] = []
        /// Absent `SPWN` chunk (issue #177) means the session spawned nothing,
        /// so no dropped item or summon rejoins the world — which is also what
        /// a save written before that chunk existed means.
        public var spawns: [SaveSpawnEntry] = []
        /// Absent `QSTS` chunk (issue #182) means no quest deviated from plugin
        /// data, so every quest re-derives its baseline from its DNAM flags —
        /// which is also what a save written before that chunk existed means.
        public var quests: [SaveQuestEntry] = []
        /// Absent `QALS` chunk (issue #183) means no quest had a filled alias
        /// table, so every running quest restores with empty aliases — which is
        /// also what a save written before that chunk existed means.
        public var questAliases: [SaveQuestAliasEntry] = []
        /// Absent QLOC means no persisted location-alias targets.
        public var questLocationAliases: [SaveQuestLocationAliasEntry] = []
        /// Absent `AVAL` chunk (issue #194) means no actor's values deviated
        /// from a full baseline, so everyone re-derives their maximums from
        /// records and starts full — which is also what a save written before
        /// that chunk existed means.
        public var actorValues: [SaveActorValueEntry] = []
        /// Absent `AVOV` chunk (issue #496) means no actor moved any
        /// actor value off the baseline its records author, so everyone
        /// re-derives the whole table — which is also what a save written
        /// before that chunk existed means.
        public var actorValueOverrides: [SaveActorValueOverrideEntry] = []
        /// Absent `DETH` chunk (issue #197) means nothing died in the session,
        /// so every actor restores alive — which is also what a save written
        /// before that chunk existed means.
        public var deaths: [SaveDeathEntry] = []
        /// Absent `CBTS` chunk (issue #374) means nothing was provoked in the
        /// session, so every actor restores neutral — which is also what a save
        /// written before that chunk existed means.
        public var combatStates: [SaveCombatStateEntry] = []
        /// Absent `DLGS` chunk (issue #426) means nobody spoke in the session,
        /// so every response restores unsaid — which is also what a save
        /// written before that chunk existed means.
        public var dialogue: [SaveDialogueEntry] = []
        /// Absent `AEFF` chunk (issue #469) means no actor carried a timed
        /// magic effect, so everyone restores with none — which is also what a
        /// save written before that chunk existed means.
        public var activeEffects: [SaveActiveEffectEntry] = []
        /// Absent `SPLB` chunk (issue #470) means nobody learned a spell, so
        /// everyone restores with an empty spellbook — which is also what a save
        /// written before that chunk existed means.
        public var spellbooks: [SaveSpellbookEntry] = []
        /// Absent `ECHG` chunk (issue #472) means nothing enchanted fired and
        /// nothing enchanted was worn, so every weapon restores fully charged and
        /// no worn item owns an effect — which is also what a save written before
        /// that chunk existed means.
        public var enchantedItems: [SaveEnchantedItemEntry] = []
        /// Absent `PRKS` chunk (issue #497) means nobody owns a perk, so every
        /// actor restores with none — which is also what a save written before
        /// that chunk existed means.
        public var perks: [SavePerkEntry] = []
        /// Absent `FCTN` chunk (issue #503) means nothing asked who anybody
        /// sides with, so every actor restores with no membership component and
        /// is seeded from its record on the next query — which is also what a
        /// save written before that chunk existed means.
        public var factions: [SaveFactionEntry] = []
        /// Absent `RELS` chunk (issue #508) means no script set a relationship
        /// rank, so every pair restores to what its `RELA` record says — which
        /// is also what a save written before that chunk existed means.
        public var relationships: [SaveRelationshipEntry] = []
        /// Absent `PLVL` chunk (issue #499) means the player never left level
        /// 1, so progress restores at the session start — which is also what a
        /// save written before that chunk existed means.
        public var playerProgress: [SavePlayerProgressEntry] = []
        /// Absent `CRIM` chunk (issue #504) means nobody committed a crime
        /// anybody charged for, so every actor restores owing nothing — which
        /// is also what a save written before that chunk existed means.
        public var crimeLedgers: [SaveCrimeLedgerEntry] = []
        /// Absent `STOL` chunk (issue #504) means nothing in any inventory was
        /// stolen, so the totals `INVN` restored are all honest goods — which
        /// is also what a save written before that chunk existed means.
        public var stolenGoods: [SaveStolenGoodsEntry] = []
        /// Absent `CRVG` chunk (issue #563) means no bounty had a violent
        /// part, so every `CRIM` row restores as non-violent gold — which is
        /// also what a save written before that chunk existed means.
        public var violentCrimeGold: [SaveViolentCrimeGoldEntry] = []
    }
}
