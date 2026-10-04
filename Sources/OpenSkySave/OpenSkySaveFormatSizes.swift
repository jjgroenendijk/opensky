// Lower bounds on one entry's size per save chunk. The decoder checks a declared count
// against the bytes left, so a corrupt length throws instead of allocating gigabytes.
// Bounds, not sizes, where an entry has optional parts; fixed widths are noted.

import Foundation

nonisolated extension OpenSkySaveFormat {
    /// Smallest number of bytes a single `RDLT` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and a zero
    /// component count (1). Used to reject an impossible entry count before
    /// any array is reserved.
    public static let minimumEntrySize = 9
    /// Smallest number of bytes a single `GVAR` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the declared-type tag (1) and the
    /// float32 value (4).
    public static let minimumGlobalEntrySize = 12
    /// Smallest number of bytes one fingerprint plugin entry can occupy: an
    /// empty name (2) plus the three stats fields (12).
    public static let minimumFingerprintEntrySize = 14
    /// Smallest number of bytes a single `PSCR` instance entry can occupy: a
    /// plugin key with an empty name (1 + 2 + 4), an empty script name (2), an
    /// empty active-state name (2), the `OnInit`-fired flag (1) and a zero
    /// variable count (4).
    public static let minimumScriptEntrySize = 16
    /// Smallest number of bytes a single `PSCR` variable can occupy: an empty
    /// declaring-script name (2), an empty variable name (2) and the value tag
    /// (1), which is the whole entry when the value is `none`.
    public static let minimumScriptVariableSize = 5
    /// Smallest number of bytes a single `INVN` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1), a zero stack
    /// count (4) and a zero equipped count (4).
    public static let minimumInventoryEntrySize = 16
    /// Bytes one `INVN` stack occupies: item FormID plus count, both `UInt32`.
    /// Fixed width, so this is the exact size rather than a lower bound.
    public static let inventoryStackSize = 8
    /// Bytes one `INVN` equipped entry occupies: a single `UInt32` FormID.
    public static let inventoryEquippedSize = 4
    /// Smallest number of bytes a single `SPWN` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the base FormID (4), an interior cell
    /// tag (1 + 4), six placement floats (24), the scale (4) and the count (4).
    /// A real entry carries a generated key and may name an exterior cell, both
    /// of which are longer, so this is a lower bound rather than the size.
    public static let minimumSpawnEntrySize = 48
    /// Smallest number of bytes a single `PTMR` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), an empty script name (2), the slot byte
    /// (1) and the two `Float64` bit patterns (8 + 8). Nothing in the entry is
    /// optional, so this is also the size of every entry whose names are
    /// empty.
    public static let minimumTimerEntrySize = 26
    /// Smallest number of bytes a single `QSTS` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the running/completed flag byte (1), a
    /// zero stage count (4) and a zero objective count (4).
    public static let minimumQuestEntrySize = 16
    /// Bytes one `QSTS` reached stage occupies: a single `UInt16` index. Fixed
    /// width, so this is the exact size rather than a lower bound.
    public static let questStageSize = 2
    /// Bytes one `QSTS` objective occupies: a `UInt16` index plus its flag
    /// byte. Fixed width, like the stage entry.
    public static let questObjectiveSize = 3
    /// Smallest number of bytes a single `QALS` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4) naming the quest, and a zero fill count
    /// (4).
    public static let minimumQuestAliasEntrySize = 11
    /// Smallest number of bytes one `QALS` fill can occupy: the alias ID (4)
    /// and a plugin key with an empty name (1 + 2 + 4). A generated key is
    /// longer, so this is a lower bound rather than the size.
    public static let minimumQuestAliasFillSize = 11
    /// Smallest number of bytes a single `AVAL` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and the three
    /// current-value floats (12). A generated key or a named cell is longer, so
    /// this is a lower bound.
    public static let minimumActorValueEntrySize = 20
    /// Smallest number of bytes a single `AVOV` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and a zero value
    /// count (4). An entry with values is longer, so this is a lower bound.
    public static let minimumActorValueOverrideEntrySize = 12
    /// Bytes one `AVOV` value record occupies: the actor-value index and the
    /// base-offset, permanent and damage floats.
    public static let actorValueOverrideRecordSize = 16
    /// Smallest number of bytes a single `DETH` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1), the dead and
    /// looted flags (2) and the "no resting transform" tag (1). A generated
    /// key, a named cell or a recorded transform is longer, so this is a lower
    /// bound.
    public static let minimumDeathEntrySize = 11
    /// Smallest `HRVS` entry: a plugin key with an empty name (1 + 2 + 4) and the
    /// "no cell" tag (1).
    public static let minimumHarvestEntrySize = 8
    /// Smallest `LOCK` entry: the smallest key and cell (8), the locked byte, the
    /// level byte, and the key FormID (4).
    public static let minimumLockEntrySize = 14
    /// Smallest `SCNS` entry: the smallest key and cell (8), the phase (4), the
    /// entered byte, and the two empty list counts (8).
    public static let minimumSceneEntrySize = 21
    /// One `SCNS` running action: index (4), start (8), timed byte, duration (4).
    public static let sceneActionRecordSize = 17
    /// `SMQS` entry: the smallest key and cell (8), the start time (8), the count (4).
    public static let minimumStoryManagerQuestEntrySize = 20
    /// `DLBS` entry: the smallest key and cell (8) and the branch FormID (4).
    public static let minimumDialogueBranchEntrySize = 12
    /// `HELP` entry: the smallest key and cell (8) and the record count (4).
    public static let minimumHelpMessageEntrySize = 12
    /// One `HELP` record: an empty event name (2), the count (4), the done byte.
    public static let minimumHelpMessageRecordSize = 7
    /// Smallest number of bytes a single `CBTS` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and the hostility
    /// byte (1). A generated key or a named cell is longer, so this is a lower
    /// bound.
    public static let minimumCombatStateEntrySize = 9
    /// Smallest number of bytes a single `DLGS` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4) naming the INFO, and the said count (4).
    /// A generated key is longer, so this is a lower bound rather than the
    /// size. No cell tag travels with the entry: an INFO is a base record that
    /// belongs to no cell, so the byte could only ever hold one value.
    public static let minimumDialogueEntrySize = 11
    /// Smallest number of bytes a single `AEFF` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and a zero effect
    /// count (4). An entry with effects is longer, so this is a lower bound.
    public static let minimumActiveEffectEntrySize = 12
    /// Smallest number of bytes one `AEFF` effect can occupy: the sequence (8),
    /// the source kind (4), a plugin key with an empty name for the source
    /// record and for the MGEF (7 each), the "no caster" and "no keyword" tags
    /// (1 each), the mode (4), the detrimental byte (1), duration, elapsed and
    /// paid-seconds words (4 each) and a zero value count (4).
    public static let minimumActiveEffectSize = 49
    /// Bytes one `AEFF` value record occupies: the actor-value index, the
    /// magnitude and the applied modifier amount.
    public static let activeEffectValueRecordSize = 12
    /// Smallest number of bytes a single `SPLB` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1), zero counts for
    /// the known, read-book and spent-power lists (4 each) and the two "no
    /// readied spell" tags (1 each). An entry with contents is longer, so this
    /// is a lower bound.
    public static let minimumSpellbookEntrySize = 21
    /// Smallest number of bytes one `SPLB` list member can occupy: a plugin key
    /// with an empty name. A generated key is longer, so this is a lower bound.
    public static let minimumSpellbookKeySize = 7
    /// Smallest number of bytes one `SPLB` spent-power record can occupy: the
    /// key lower bound plus the whole game day it was spent on.
    public static let minimumSpellbookPowerSize = 11
    /// Smallest number of bytes a single `ECHG` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and zero counts for
    /// the charge and worn-item lists (4 each). An entry with contents is
    /// longer, so this is a lower bound.
    public static let minimumEnchantedItemEntrySize = 16
    /// Bytes one `ECHG` charge record occupies: the item FormID and the
    /// remaining charge.
    public static let enchantedItemChargeRecordSize = 8
    /// Smallest number of bytes one `ECHG` worn-item record can occupy: the item
    /// FormID (4) and a zero sequence count (4).
    public static let minimumEnchantedItemWornSize = 8
    /// Bytes one `ECHG` worn-effect sequence occupies.
    public static let enchantedItemSequenceSize = 8
    /// Smallest number of bytes a single `PRKS` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and a zero owned
    /// count (4). An entry with contents is longer, so this is a lower bound.
    public static let minimumPerkEntrySize = 12
    /// Smallest number of bytes one `PRKS` owned perk can occupy: a plugin key
    /// with an empty name. A generated key is longer, so this is a lower bound.
    public static let minimumPerkKeySize = 7
    /// Smallest number of bytes a single `FCTN` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and a zero
    /// membership count (4). An entry with contents is longer, so this is a
    /// lower bound.
    public static let minimumFactionEntrySize = 12
    /// Smallest number of bytes one `FCTN` membership can occupy: a plugin key
    /// with an empty name (7) and the signed rank byte. A generated key is
    /// longer, so this is a lower bound.
    public static let minimumFactionMembershipSize = 8
    /// Smallest number of bytes a single `RELS` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and a zero
    /// override count (4). An entry with contents is longer, so this is a lower
    /// bound.
    public static let minimumRelationshipEntrySize = 12
    /// Smallest number of bytes one `RELS` override can occupy: a plugin key
    /// with an empty name (7) and the signed rank byte. A generated key is
    /// longer, so this is a lower bound.
    public static let minimumRelationshipOverrideSize = 8
    /// Smallest number of bytes a single `PLVL` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the level, experience, perk points,
    /// pending picks and skill increases (4 each) and a zero pick-history count
    /// (4). Nothing but the key and the history is variable, so this is a lower
    /// bound only because a generated key is longer.
    public static let minimumPlayerProgressEntrySize = 31
    /// Bytes one `PLVL` attribute pick occupies: the vanilla actor-value index
    /// it names. Fixed width, so this is the exact size.
    public static let playerProgressPickSize = 4
    /// Smallest number of bytes a single `CRIM` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and a zero row
    /// count (4). An entry with contents is longer, so this is a lower bound.
    public static let minimumCrimeLedgerEntrySize = 12
    /// Smallest number of bytes one `CRIM` row can occupy: a plugin key with an
    /// empty name (7), the gold (4) and one count per `CrimeKind` (4 each). A
    /// generated key is longer, so this is a lower bound.
    public static let minimumCrimeLedgerRowSize = 27
    /// Smallest number of bytes a single `STOL` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4) and a zero row count (4). There is no
    /// cell tag — the stolen split belongs to the goods, not to a placement.
    public static let minimumStolenGoodsEntrySize = 11
    /// Bytes one `STOL` row occupies: the item FormID and the stolen count.
    /// Fixed width, so this is the exact size.
    public static let stolenGoodsRowSize = 8
    /// Smallest number of bytes a single `CRVG` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4) and a zero row count (4).
    public static let minimumViolentCrimeGoldEntrySize = 11
    /// Smallest number of bytes one `CRVG` row can occupy: a plugin key with an
    /// empty name (7) and the violent gold (4).
    public static let minimumViolentCrimeGoldRowSize = 11
}
