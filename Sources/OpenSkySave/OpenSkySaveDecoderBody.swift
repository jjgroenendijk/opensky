// The decoder's parsed-chunk bag: what each chunk decodes into, and what an absent
// chunk means, which is the compatibility contract. `OpenSkySaveDecoder.swift` routes
// chunks. A nested `internal` type so the parent keeps saying `Body`.

import Foundation
import OpenSkyActorsInterface
import OpenSkyDialogueInterface
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
import OpenSkyWorldInterface
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
        /// Absent `CLOK`: the vanilla-start clock.
        public var clock: GameClock?
        /// Absent `PLOC`: the load leaves the player where they stand.
        public var playerPlace: SavePlayerPlace?
        /// Absent `PSCR`: every script starts from its compiled defaults.
        public var scripts: [PapyrusInstanceState] = []
        /// Absent `PTMR`: no update timer was pending.
        public var timers: [PapyrusTimerState] = []
        /// Absent `INVN`: every container and actor re-derives its contents from records.
        public var inventories: [SaveInventoryEntry] = []
        /// Absent `SPWN`: no dropped item or summon rejoins the world.
        public var spawns: [SaveSpawnEntry] = []
        /// Absent `QSTS`: every quest re-derives its baseline from its DNAM flags.
        public var quests: [SaveQuestEntry] = []
        /// Absent `QALS`: every running quest restores with empty aliases.
        public var questAliases: [SaveQuestAliasEntry] = []
        /// Absent QLOC means no persisted location-alias targets.
        public var questLocationAliases: [SaveQuestLocationAliasEntry] = []
        /// Absent `AVAL`: everyone re-derives their maximums and starts full.
        public var actorValues: [SaveActorValueEntry] = []
        /// Absent `AVOV`: everyone re-derives the whole actor-value table.
        public var actorValueOverrides: [SaveActorValueOverrideEntry] = []
        /// Absent `DETH`: every actor restores alive.
        public var deaths: [SaveDeathEntry] = []
        /// Absent `CBTS`: every actor restores neutral.
        public var combatStates: [SaveCombatStateEntry] = []
        /// Absent `DLGS`: every response restores unsaid.
        public var dialogue: [SaveDialogueEntry] = []
        /// Absent `AEFF`: no actor carries a timed magic effect.
        public var activeEffects: [SaveActiveEffectEntry] = []
        /// Absent `SPLB`: everyone restores with an empty spellbook.
        public var spellbooks: [SaveSpellbookEntry] = []
        /// Absent `ECHG`: every weapon is fully charged and no worn item owns an effect.
        public var enchantedItems: [SaveEnchantedItemEntry] = []
        /// Absent `PRKS`: nobody owns a perk.
        public var perks: [SavePerkEntry] = []
        /// Absent `FCTN`: no membership component; each actor is seeded from its record
        /// on the next query.
        public var factions: [SaveFactionEntry] = []
        /// Absent `RELS`: every pair restores to its `RELA` record.
        public var relationships: [SaveRelationshipEntry] = []
        /// Absent `PLVL`: the player is still level 1.
        public var playerProgress: [SavePlayerProgressEntry] = []
        /// Absent `CRIM`: nobody owes anything.
        public var crimeLedgers: [SaveCrimeLedgerEntry] = []
        /// Absent `STOL`: every `INVN` item is honest.
        public var stolenGoods: [SaveStolenGoodsEntry] = []
        /// Absent `CRVG`: every `CRIM` row is non-violent gold.
        public var violentCrimeGold: [SaveViolentCrimeGoldEntry] = []
        /// Absent `HRVS`: every plant is unharvested.
        public var harvests: [SaveHarvestEntry] = []
        /// Absent `HRVD`: no harvest has a known day, so none grows back.
        public var harvestDays: [SaveHarvestDayEntry] = []
        /// Absent `LOCK`: every lock is as its plugin placed it.
        public var locks: [SaveLockEntry] = []
        /// Absent `SCNS`: no scene is playing.
        public var scenes: [SaveStoryEntry<SceneRuntimeState>] = []
        /// Absent `SMQS`: the story manager started no quest.
        public var storyManagerQuests: [SaveStoryEntry<StoryManagerQuestState>] = []
        /// Absent `DLBS`: no speaker is in an exclusive branch.
        public var dialogueBranches: [SaveStoryEntry<DialogueBranchState>] = []
        public var helpMessages: [SaveStoryEntry<HelpMessageState>] = []
        /// Absent `PIDN`: the player is the vanilla `Player` record.
        public var identities: [SaveStoryEntry<PlayerIdentityState>] = []
        /// Absent `MRKS`: every marker is as its record flags say.
        public var markers: [SaveStoryEntry<MapMarkerState>] = []
        /// Absent `FOGM`: the local map is fogged everywhere.
        public var fog: [SaveStoryEntry<LocalMapFogState>] = []
    }
}
