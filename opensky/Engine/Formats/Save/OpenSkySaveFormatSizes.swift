// Lower bounds on the size of one entry inside each OpenSky save chunk.
//
// A satellite of `OpenSkySaveFormat` for the reason the AEFF and SPLB writers
// are satellites of the encoder: the parent is at its file-length cap. Every
// constant here answers one question the decoder asks before it reserves an
// array — "can the bytes actually left possibly hold the count this chunk just
// declared?" — so a corrupt length is a thrown error rather than a
// multi-gigabyte allocation.
//
// They are lower bounds, not sizes, wherever an entry carries something
// optional: a generated key is longer than a plugin key with an empty name, and
// a named cell is longer than the "no cell" tag. Where an entry is fixed width
// the comment says so.

import Foundation

nonisolated extension OpenSkySaveFormat {
    /// Smallest number of bytes a single `RDLT` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and a zero
    /// component count (1). Used to reject an impossible entry count before
    /// any array is reserved.
    static let minimumEntrySize = 9
    /// Smallest number of bytes a single `GVAR` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the declared-type tag (1) and the
    /// float32 value (4).
    static let minimumGlobalEntrySize = 12
    /// Smallest number of bytes one fingerprint plugin entry can occupy: an
    /// empty name (2) plus the three stats fields (12).
    static let minimumFingerprintEntrySize = 14
    /// Smallest number of bytes a single `PSCR` instance entry can occupy: a
    /// plugin key with an empty name (1 + 2 + 4), an empty script name (2), an
    /// empty active-state name (2), the `OnInit`-fired flag (1) and a zero
    /// variable count (4).
    static let minimumScriptEntrySize = 16
    /// Smallest number of bytes a single `PSCR` variable can occupy: an empty
    /// declaring-script name (2), an empty variable name (2) and the value tag
    /// (1), which is the whole entry when the value is `none`.
    static let minimumScriptVariableSize = 5
    /// Smallest number of bytes a single `INVN` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1), a zero stack
    /// count (4) and a zero equipped count (4).
    static let minimumInventoryEntrySize = 16
    /// Bytes one `INVN` stack occupies: item FormID plus count, both `UInt32`.
    /// Fixed width, so this is the exact size rather than a lower bound.
    static let inventoryStackSize = 8
    /// Bytes one `INVN` equipped entry occupies: a single `UInt32` FormID.
    static let inventoryEquippedSize = 4
    /// Smallest number of bytes a single `SPWN` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the base FormID (4), an interior cell
    /// tag (1 + 4), six placement floats (24), the scale (4) and the count (4).
    /// A real entry carries a generated key and may name an exterior cell, both
    /// of which are longer, so this is a lower bound rather than the size.
    static let minimumSpawnEntrySize = 48
    /// Smallest number of bytes a single `PTMR` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), an empty script name (2), the slot byte
    /// (1) and the two `Float64` bit patterns (8 + 8). Nothing in the entry is
    /// optional, so this is also the size of every entry whose names are
    /// empty.
    static let minimumTimerEntrySize = 26
    /// Smallest number of bytes a single `QSTS` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the running/completed flag byte (1), a
    /// zero stage count (4) and a zero objective count (4).
    static let minimumQuestEntrySize = 16
    /// Bytes one `QSTS` reached stage occupies: a single `UInt16` index. Fixed
    /// width, so this is the exact size rather than a lower bound.
    static let questStageSize = 2
    /// Bytes one `QSTS` objective occupies: a `UInt16` index plus its flag
    /// byte. Fixed width, like the stage entry.
    static let questObjectiveSize = 3
    /// Smallest number of bytes a single `QALS` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4) naming the quest, and a zero fill count
    /// (4).
    static let minimumQuestAliasEntrySize = 11
    /// Smallest number of bytes one `QALS` fill can occupy: the alias ID (4)
    /// and a plugin key with an empty name (1 + 2 + 4). A generated key is
    /// longer, so this is a lower bound rather than the size.
    static let minimumQuestAliasFillSize = 11
    /// Smallest number of bytes a single `AVAL` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and the three
    /// current-value floats (12). A generated key or a named cell is longer, so
    /// this is a lower bound.
    static let minimumActorValueEntrySize = 20
    /// Smallest number of bytes a single `AVGN` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and a zero value
    /// count (4). An entry with values is longer, so this is a lower bound.
    static let minimumGeneralActorValueEntrySize = 12
    /// Bytes one `AVGN` value record occupies: the actor-value index and the
    /// base, permanent and damage floats.
    static let generalActorValueRecordSize = 16
    /// Smallest number of bytes a single `DETH` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1), the dead and
    /// looted flags (2) and the "no resting transform" tag (1). A generated
    /// key, a named cell or a recorded transform is longer, so this is a lower
    /// bound.
    static let minimumDeathEntrySize = 11
    /// Smallest number of bytes a single `CBTS` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and the hostility
    /// byte (1). A generated key or a named cell is longer, so this is a lower
    /// bound.
    static let minimumCombatStateEntrySize = 9
    /// Smallest number of bytes a single `DLGS` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4) naming the INFO, and the said count (4).
    /// A generated key is longer, so this is a lower bound rather than the
    /// size. No cell tag travels with the entry: an INFO is a base record that
    /// belongs to no cell, so the byte could only ever hold one value.
    static let minimumDialogueEntrySize = 11
    /// Smallest number of bytes a single `AEFF` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and a zero effect
    /// count (4). An entry with effects is longer, so this is a lower bound.
    static let minimumActiveEffectEntrySize = 12
    /// Smallest number of bytes one `AEFF` effect can occupy: the sequence (8),
    /// the source kind (4), a plugin key with an empty name for the source
    /// record and for the MGEF (7 each), the "no caster" and "no keyword" tags
    /// (1 each), the mode (4), the detrimental byte (1), duration, elapsed and
    /// paid-seconds words (4 each) and a zero value count (4).
    static let minimumActiveEffectSize = 49
    /// Bytes one `AEFF` value record occupies: the actor-value index, the
    /// magnitude and the applied modifier amount.
    static let activeEffectValueRecordSize = 12
    /// Smallest number of bytes a single `SPLB` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1), zero counts for
    /// the known, read-book and spent-power lists (4 each) and the two "no
    /// readied spell" tags (1 each). An entry with contents is longer, so this
    /// is a lower bound.
    static let minimumSpellbookEntrySize = 21
    /// Smallest number of bytes one `SPLB` list member can occupy: a plugin key
    /// with an empty name. A generated key is longer, so this is a lower bound.
    static let minimumSpellbookKeySize = 7
    /// Smallest number of bytes one `SPLB` spent-power record can occupy: the
    /// key lower bound plus the whole game day it was spent on.
    static let minimumSpellbookPowerSize = 11
    /// Smallest number of bytes a single `ECHG` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and zero counts for
    /// the charge and worn-item lists (4 each). An entry with contents is
    /// longer, so this is a lower bound.
    static let minimumEnchantedItemEntrySize = 16
    /// Bytes one `ECHG` charge record occupies: the item FormID and the
    /// remaining charge.
    static let enchantedItemChargeRecordSize = 8
    /// Smallest number of bytes one `ECHG` worn-item record can occupy: the item
    /// FormID (4) and a zero sequence count (4).
    static let minimumEnchantedItemWornSize = 8
    /// Bytes one `ECHG` worn-effect sequence occupies.
    static let enchantedItemSequenceSize = 8
}
