// OpenSky's own save format, not Bethesda's `.ess`. Bytes after the header are a pure
// function of the snapshot and fingerprint. The body is tagged chunks: a new chunk is
// additive (older builds skip it, and an untouched session writes none), while a
// component kind inside `RDLT` is versioned by `formatVersion`. Every count is checked
// against the remaining bytes before an allocation. See docs/formats/opensky-save.md.

import Foundation

/// Names and version constants of the OpenSky native save container.
nonisolated public enum OpenSkySaveFormat: Sendable {
    /// File magic: ASCII "OSAV", four bytes, first in the file.
    public static let magic = Data("OSAV".utf8)
    /// Version of the layout this build writes and is the only one it reads.
    public static let currentVersion: UInt32 = 1
    /// File extension for saves written by this engine.
    public static let fileExtension = "osav"

    /// Four-character chunk tags defined in version 1.
    public enum ChunkTag: Sendable {
        /// Generated-reference allocator position. Payload is exactly one
        /// `UInt64`.
        public static let allocator = "GALC"
        /// Runtime reference deltas, one entry per dirty reference.
        public static let referenceDeltas = "RDLT"
        /// Runtime global overrides, one entry per global. An additive chunk, so
        /// `currentVersion` did not change.
        public static let globalValues = "GVAR"
        /// Game clock: one `Float64` bit pattern, `GameClock.totalGameSeconds`. Absent
        /// restores the vanilla-start clock.
        public static let clock = "CLOK"
        /// Papyrus script instances with their variables. A chunk, not an `RDLT`
        /// component kind, so older builds skip it instead of refusing the file.
        public static let papyrusScripts = "PSCR"
        /// Pending Papyrus update timers, one entry per armed slot of a persistent
        /// instance. No armed timer writes no chunk.
        public static let papyrusTimers = "PTMR"
        /// Runtime inventories: stacks and equipped set per deviating owner. Kept out of
        /// `RDLT` (an entry whose only component is inventory is omitted there), so older
        /// builds still load the save. The decoder merges both back into one delta.
        public static let inventories = "INVN"
        /// Spawned references, such as dropped items. A chunk for the same reason as
        /// `INVN`.
        public static let spawnedReferences = "SPWN"
        /// Quest runtime state: running, stage and objective deviations per quest.
        public static let questStates = "QSTS"
        /// Filled quest aliases per quest. A sibling of `QSTS`: its entries have no
        /// per-entry length, so appending a field would break older readers.
        public static let questAliases = "QALS"
        /// Filled location aliases. Separate from QALS so old readers skip
        /// location targets instead of misparsing QALS's flat entries.
        public static let questLocationAliases = "QLOC"
        /// Actor values: current health, magicka and stamina below full. Current values
        /// only; maximums come from the records.
        public static let actorValues = "AVAL"

        /// Actor-value overrides: index, base offset, permanent and damage modifier per
        /// value. A sibling of `AVAL` (fixed layout). It replaced `AVGN`, which stored an
        /// absolute base, under a new tag so neither is misread as the other. The
        /// temporary modifier is skipped: `AEFF` rebuilds it, so saving it would double it.
        public static let actorValueOverrides = "AVOV"

        /// Death states with the resting root transform. Not the per-bone pose, so a
        /// reloaded corpse lies in rest pose (docs/engine/ragdoll.md).
        public static let deaths = "DETH"

        /// Hostility toward the player, where not neutral. The player's own combat state
        /// is derived, so it is not saved.
        public static let combatStates = "CBTS"

        /// Dialogue said-state, one entry per said INFO. Offered topics are derived from
        /// records and quest state, so they are not saved.
        public static let dialogueStates = "DLGS"
        /// The game day each speaker last said an INFO with a reset time. Apart
        /// from `DLGS`, so an older build skips it and still loads the counts.
        public static let dialogueSaidDays = "DLGT"

        /// Active timed magic effects per actor, with remaining duration. Each owns part
        /// of a temporary slot, which load rebuilds from here. Instant effects already
        /// live in `AVAL` and `AVOV`.
        public static let activeEffects = "AEFF"

        /// Spellbooks: known spells, read books, spent powers and readied hands. A cast in
        /// progress is frame state and is not saved.
        public static let spellbooks = "SPLB"

        /// Enchanted items: spent weapon charge and the `AEFF` effects each worn item owns.
        /// Not in `INVN`, whose entries are counts; both halves stay together so reloaded
        /// effects can be taken off.
        public static let enchantedItems = "ECHG"

        /// Owned perks per actor. Ranks come from the `NNAM` chain and perk abilities
        /// are rebuilt on load, so neither is stored.
        public static let perks = "PRKS"

        /// Faction memberships per actor. Hostility is derived from these and the
        /// records, so it is not saved; `CBTS` holds only the explicit override.
        public static let factions = "FCTN"

        /// Scripted relationship ranks: per actor, one row per other actor. Both
        /// directions are stored, as `RelationshipRuntime` writes both.
        public static let relationships = "RELS"

        /// The player's level progress, only after level 1: level, banked experience,
        /// perk points, owed and made picks. A pick's points live in `AVOV`.
        public static let playerProgress = "PLVL"

        /// Crime ledgers: per faction, the bounty and four crime counts. An unwitnessed
        /// crime moves a count but not the gold (<https://en.uesp.net/wiki/Skyrim:Crime>).
        public static let crimeLedgers = "CRIM"

        /// Stolen goods: per owner, one row per item with its stolen count. A sibling of
        /// `INVN`, which keeps the summed totals so older builds read a full inventory.
        public static let stolenGoods = "STOL"

        /// Tempered copies: per owner and item, one quality level per improved copy.
        /// A sibling of `INVN`, whose rows have no room for a quality.
        public static let temperedItems = "TMPR"

        /// Violent crime gold: per faction, the violent part of the `CRIM` row. A sibling,
        /// because `CRIM` rows have a fixed layout; `CRIM` keeps the total.
        public static let violentCrimeGold = "CRVG"

        /// Harvested flora and trees. Presence means harvested.
        public static let harvests = "HRVS"
        /// The game day of each timed harvest. Additive beside `HRVS`, so an older
        /// build skips it and keeps the plant harvested.
        public static let harvestDays = "HRVD"
        /// Runtime lock state of doors and containers.
        public static let locks = "LOCK"
        /// References moved into another cell, and the cell that draws them.
        public static let relocations = "RLOC"
        /// Playing scenes: phase, started actions, and completed actions.
        public static let scenes = "SCNS"
        /// Quests the story manager started: last start time and start count.
        public static let storyManagerQuests = "SMQS"
        /// Speakers in an exclusive dialogue branch.
        public static let dialogueBranches = "DLBS"
        /// Help messages per input event: times shown and whether the event happened.
        public static let helpMessages = "HELP"
    }

    /// Discriminator byte in front of a serialized `ReferenceKey`.
    public enum KeyTag: Sendable {
        public static let plugin: UInt8 = 0
        public static let generated: UInt8 = 1
    }

    /// Discriminator byte in front of a serialized `CellSceneLocation`.
    public enum CellTag: Sendable {
        public static let absent: UInt8 = 0
        public static let exterior: UInt8 = 1
        public static let interior: UInt8 = 2
    }

    /// Discriminator byte in front of a serialized `PapyrusValue` in `PSCR`.
    ///
    /// Only the five persistable kinds have a tag. `PapyrusValue.object` and
    /// `.array` hold runtime-allocated identity with no world meaning, so the
    /// encoder writes them as `none` rather than inventing a wire shape for a
    /// handle that means nothing after a reload.
    public enum ValueTag: Sendable {
        public static let none: UInt8 = 0
        public static let boolean: UInt8 = 1
        public static let integer: UInt8 = 2
        public static let float: UInt8 = 3
        public static let string: UInt8 = 4
    }

    /// Bits of a `QSTS` entry's quest-level flag byte. Ours, not Bethesda's:
    /// the DNAM bits a QUST record carries describe what the plugin authored,
    /// while these two describe what the session did.
    public enum QuestFlag: Sendable {
        public static let running: UInt8 = 1 << 0
        public static let completed: UInt8 = 1 << 1
    }

    /// Bits of a `QSTS` objective's flag byte, in the order the three Papyrus
    /// natives are usually called: displayed, completed, failed.
    public enum QuestObjectiveFlag: Sendable {
        public static let displayed: UInt8 = 1 << 0
        public static let completed: UInt8 = 1 << 1
        public static let failed: UInt8 = 1 << 2
    }
}
