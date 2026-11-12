// The decoder's parsed-chunk bag: what each chunk decodes into, and what an absent
// chunk means, which is the compatibility contract. `OpenSkySaveDecoder.swift` routes
// chunks. A nested `internal` type so the parent keeps saying `Body`.

import Foundation
public import OpenSkyActorsInterface
public import OpenSkyCrimeInterface
public import OpenSkyDialogueInterface
public import OpenSkyFormatsESM
public import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
public import OpenSkyQuestsInterface
public import OpenSkySaveInterface
public import OpenSkyScriptingInterface
public import OpenSkyWorldInterface
public import OpenSkyWorldState

nonisolated extension OpenSkySaveDecoder {
    /// Parsed chunk payloads, with the defaults an absent chunk implies.
    public struct Body: Sendable {
        var entries: [WorldStateSnapshotEntry] = []
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
        var inventories: [SaveInventoryEntry] = []
        /// Absent `SPWN`: no dropped item or summon rejoins the world.
        var spawns: [SaveSpawnEntry] = []
        /// Absent `QSTS`: every quest re-derives its baseline from its DNAM flags.
        var quests: [SaveQuestEntry] = []
        /// Absent `QALS`: every running quest restores with empty aliases.
        var questAliases: [SaveQuestAliasEntry] = []
        /// Absent QLOC means no persisted location-alias targets.
        var questLocationAliases: [SaveQuestLocationAliasEntry] = []
        /// Absent `QJLG`: the journal shows each quest's highest reached stage.
        var questJournalLogs: [ReferenceKey: QuestJournalLog] = [:]
        /// Absent `AVAL`: everyone re-derives their maximums and starts full.
        var actorValues: [SaveActorValueEntry] = []
        /// Absent `AVOV`: everyone re-derives the whole actor-value table.
        var actorValueOverrides: [SaveActorValueOverrideEntry] = []
        /// Absent `DETH`: every actor restores alive.
        var deaths: [SaveDeathEntry] = []
        /// Absent `CBTS`: every actor restores neutral.
        var combatStates: [SaveCombatStateEntry] = []
        /// Absent `DLGS`: every response restores unsaid.
        var dialogue: [SaveDialogueEntry] = []
        /// Absent `DLGT`: no said response waits for its reset time.
        var dialogueSaidDays: [ReferenceKey: [ReferenceKey: Double]] = [:]
        /// Absent `AEFF`: no actor carries a timed magic effect.
        var activeEffects: [SaveActiveEffectEntry] = []
        /// Absent `SPLB`: everyone restores with an empty spellbook.
        var spellbooks: [SaveSpellbookEntry] = []
        /// Absent `ECHG`: every weapon is fully charged and no worn item owns an effect.
        var enchantedItems: [SaveEnchantedItemEntry] = []
        /// Absent `PRKS`: nobody owns a perk.
        var perks: [SavePerkEntry] = []
        /// Absent `FCTN`: no membership component; each actor is seeded from its record
        /// on the next query.
        var factions: [SaveFactionEntry] = []
        /// Absent `RELS`: every pair restores to its `RELA` record.
        var relationships: [SaveRelationshipEntry] = []
        /// Absent `PLVL`: the player is still level 1.
        var playerProgress: [SavePlayerProgressEntry] = []
        var legendarySkills: [ReferenceKey: [Int32: Int]] = [:]
        var trainingSessions: [ReferenceKey: Int] = [:]
        /// Absent `CRIM`: nobody owes anything.
        var crimeLedgers: [SaveCrimeLedgerEntry] = []
        /// Absent `STOL`: every `INVN` item is honest.
        var stolenGoods: [SaveStolenGoodsEntry] = []
        /// The chunks that lay over the core entries: items, alchemy, crime, harvests,
        /// locks, placement, scenes, story state, and the map.
        var side = OpenSkySaveSideChunks()
    }
}

/// The decoder's side chunks, with the defaults an absent chunk implies.
nonisolated struct OpenSkySaveSideChunks: Sendable {
    /// Absent `TMPR`: every held copy is plain.
    var temperedItems: [SaveTemperedItemEntry] = []
    var itemCopies: [SaveTemperedItemEntry] = []
    /// Absent `CPOT`: the player brewed nothing.
    var createdPotions: [SaveStoryEntry<CreatedPotionState>] = []
    /// Absent `INGK`: no ingredient effect is known.
    var ingredientKnowledge: [SaveStoryEntry<IngredientKnowledgeState>] = []
    /// Absent `WPSN`: no weapon is poisoned.
    var weaponPoisons: [SaveStoryEntry<WeaponPoisonState>] = []
    /// Absent `FAVS`: no item is a favourite.
    var favourites: [SaveStoryEntry<FavouritesState>] = []
    /// Absent `ENCK`: no enchantment is known or made.
    var enchanting: [SaveStoryEntry<EnchantingState>] = []
    /// Absent `CRVG`: every `CRIM` row is non-violent gold.
    var violentCrimeGold: [SaveViolentCrimeGoldEntry] = []
    var relationshipFavour: [SaveRelationshipFavourEntry] = []
    var stolenOrigins: [SaveStoryEntry<StolenOriginsState>] = []
    /// Absent `HRVS`: every plant is unharvested.
    var harvests: [SaveHarvestEntry] = []
    /// Absent `HRVD`: no harvest has a known day, so none grows back.
    var harvestDays: [SaveHarvestDayEntry] = []
    /// Absent `LOCK`: every lock is as its plugin placed it.
    var locks: [SaveLockEntry] = []
    /// Absent `CRST`: no cell has a departure, so none resets on the next visit.
    var cellResets: [SaveCellResetLedger] = []
    var vendorRestocks: [SaveVendorRestockLedger] = []
    /// Absent `RLOC`: every reference is in its plugin cell.
    var relocations: [SaveRelocationEntry] = []
    var motionTypes: [SaveMotionTypeEntry] = []
    /// Absent `LVRL`: every reference rolls at the live player level.
    var leveledRolls: [SaveLeveledRollEntry] = []
    /// Absent `SCNS`: no scene is playing.
    var scenes: [SaveStoryEntry<SceneRuntimeState>] = []
    /// Absent `SCNP`: no scene is paused. Each entry holds only `pausedAt`.
    var scenePauses: [SaveStoryEntry<SceneRuntimeState>] = []
    /// Absent `SMQS`: the story manager started no quest.
    var storyManagerQuests: [SaveStoryEntry<StoryManagerQuestState>] = []
    /// Absent `DLBS`: no speaker is in an exclusive branch.
    var dialogueBranches: [SaveStoryEntry<DialogueBranchState>] = []
    var helpMessages: [SaveStoryEntry<HelpMessageState>] = []
    /// Absent `PRUL`: god mode is off and the player's crimes are reported.
    var playerRules: [SaveStoryEntry<PlayerRuleSwitches>] = []
    /// Absent `SCRS`: no script set a flag the save keeps.
    var scriptedStates: [SaveStoryEntry<ScriptedReferenceState>] = []
    /// Absent `MSTS`: no stat was counted.
    var miscStats: [SaveStoryEntry<MiscStatsState>] = []
    /// Absent `QTRK`: the journal showed no quest.
    var questTracking: [SaveStoryEntry<QuestTrackingState>] = []
    /// Absent `PIDN`: the player is the vanilla `Player` record.
    var identities: [SaveStoryEntry<PlayerIdentityState>] = []
    /// Absent `PCPX`: each identity keeps its race's default face texture.
    var complexions: [ReferenceKey: FormID] = [:]
    /// Absent `MRKS`: every marker is as its record flags say.
    var markers: [SaveStoryEntry<MapMarkerState>] = []
    /// Absent `FOGM`: the local map is fogged everywhere.
    var fog: [SaveStoryEntry<LocalMapFogState>] = []
    /// Absent `PMRK`: the player placed no marker.
    var playerMarkers: [SaveStoryEntry<PlayerSetMapMarker>] = []
}
