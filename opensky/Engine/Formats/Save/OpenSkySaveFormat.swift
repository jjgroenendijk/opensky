// OpenSky native save container (issue #161, roadmap item 10.1.4): the on-disk
// shape of a saved session.
//
// This is OpenSky's own format, not Bethesda's `.ess`. Nothing here is reverse
// engineered, so the layout is chosen for the properties this engine needs:
//
// - Deterministic bytes. Everything after the header metadata is a pure
//   function of the `WorldStateSnapshot` plus the load-order fingerprint, so
//   two sessions that reached the same end state through different mutation
//   orders write byte-identical files. Nothing in the encoder reads the clock
//   or a hash seed; the creation timestamp is injected by the caller and lives
//   in the header, outside the deterministic region.
// - Forward and backward tolerance. The body is a stream of tagged chunks, so
//   an older build skips a chunk a newer build added instead of refusing the
//   file. Component kinds inside a chunk are the opposite: they are versioned
//   by `formatVersion`, because a delta whose components were partly dropped
//   is a silently wrong world, not a degraded one.
// - Defensive decoding. Every count is checked against the bytes actually
//   remaining before an array is sized, so a corrupt length cannot make the
//   decoder allocate gigabytes (AGENTS.md: malformed input must not crash).
//
// Documented in docs/formats/opensky-save.md.

import Foundation

/// Names and version constants of the OpenSky native save container.
nonisolated enum OpenSkySaveFormat {
    /// File magic: ASCII "OSAV", four bytes, first in the file.
    static let magic = Data("OSAV".utf8)
    /// Version of the layout this build writes and is the only one it reads.
    static let currentVersion: UInt32 = 1
    /// File extension for saves written by this engine.
    static let fileExtension = "osav"

    /// Four-character chunk tags defined in version 1.
    enum ChunkTag {
        /// Generated-reference allocator position. Payload is exactly one
        /// `UInt64`.
        static let allocator = "GALC"
        /// Runtime reference deltas, one entry per dirty reference.
        static let referenceDeltas = "RDLT"
        /// Runtime global-variable overrides, one entry per overridden global
        /// (issue #165). Added after version 1 shipped and deliberately did not
        /// bump `currentVersion`: it is a new chunk, so an older build skips it
        /// by its declared length and loads the rest of the save, which is the
        /// tolerance the chunk stream exists to provide.
        static let globalValues = "GVAR"
        /// Game clock state (issue #164). Payload is exactly one `Float64`
        /// bit pattern: `GameClock.totalGameSeconds`. Additive like `GVAR` —
        /// an older build skips it, and a file without it restores the
        /// vanilla-start clock.
        static let clock = "CLOK"
        /// Papyrus script instance state (issue #171): one entry per live
        /// script instance, with its variables. Additive like `GVAR` and
        /// `CLOK` and deliberately does not bump `currentVersion` — an older
        /// build skips it by its declared length and loads the rest of the
        /// save, and a file without it restores a world whose scripts start
        /// from their compiled defaults. Script state is a new chunk rather
        /// than a new component kind inside `RDLT` for exactly this reason: a
        /// component kind is versioned by `formatVersion`, so putting it there
        /// would force every older build to refuse the file.
        static let papyrusScripts = "PSCR"
        /// Pending Papyrus update timers (issue #277): one entry per armed
        /// timer slot of a persistent script instance. Additive for the same
        /// reasons `PSCR` is and likewise does not bump `currentVersion` — an
        /// older build skips it by its declared length, and a file without it
        /// restores a world where no script has a pending `OnUpdate`. An empty
        /// timer list writes no chunk at all, so a session that armed no timer
        /// produces the bytes it produced before this chunk existed.
        static let papyrusTimers = "PTMR"
        /// Runtime inventories (issue #176): one entry per owner whose items
        /// deviate from plugin data, with its stacks and its equipped set.
        ///
        /// Inventory is a `WorldStateComponentKind` in the store but is *not*
        /// written inside `RDLT`, and that split is the whole point. A
        /// component kind inside `RDLT` is versioned by `formatVersion`, so
        /// putting inventory there would force every older build to refuse
        /// every save that has one. As its own chunk it is additive like
        /// `GVAR`, `CLOK`, `PSCR` and `PTMR`: an older build skips it by its
        /// declared length and loads the rest of the world. `RDLT` therefore
        /// omits the inventory component entirely, and omits an entry whose
        /// only component was inventory, so an older build sees exactly the
        /// bytes it would have written itself. The decoder merges the two back
        /// into one delta per reference. An owner with no runtime inventory
        /// writes nothing, and a session that touched none writes no chunk.
        static let inventories = "INVN"
        /// Spawned references (issue #177): one entry per object the running
        /// game placed in the world, such as a dropped item.
        ///
        /// Additive for the same reason `INVN` is, and split out for the same
        /// reason: a component kind inside `RDLT` is versioned by
        /// `formatVersion`, so an older build would refuse every save that
        /// contained one instead of loading the rest of the world without the
        /// dropped items. A session that spawned nothing writes no chunk.
        static let spawnedReferences = "SPWN"
        /// Quest runtime state (issue #182): one entry per quest whose running,
        /// stage or objective state deviates from plugin data.
        ///
        /// Additive for the same reason `INVN` and `SPWN` are, and split out of
        /// `RDLT` for the same reason: a component kind inside `RDLT` is
        /// versioned by `formatVersion`, so an older build would refuse every
        /// save containing quest state instead of loading the rest of the
        /// world. A session that touched no quest writes no chunk, so its bytes
        /// match what this encoder produced before the chunk existed.
        static let questStates = "QSTS"
        /// Filled quest aliases (issue #183): one entry per quest whose alias
        /// table is non-empty, and inside it one fill per filled alias.
        ///
        /// A sibling of `QSTS` rather than an extension of it, decided here
        /// because the two answer to different rules. `QSTS` entries are a flat
        /// positional layout with no per-entry length, so appending a field to
        /// them would make every older build misparse the *whole* chunk rather
        /// than skip the new part — the exact failure the chunk stream exists
        /// to avoid. As its own chunk the fills are additive like `INVN` and
        /// `SPWN`: an older build skips them by the declared length and
        /// restores a world whose quests run with empty aliases, and a session
        /// that filled none writes no chunk at all.
        static let questAliases = "QALS"
        /// Actor values (issue #194): one entry per actor whose current
        /// health, magicka or stamina deviates from a full baseline.
        ///
        /// Additive and split out of `RDLT` for the same reason `INVN`, `SPWN`,
        /// `QSTS` and `QALS` are: a component kind inside `RDLT` is versioned
        /// by `formatVersion`, so an older build would refuse every save
        /// containing a wounded actor instead of loading the rest of the world
        /// with everyone at full health. A session in which nothing took damage
        /// writes no chunk at all.
        ///
        /// Current values only. The maximums are a pure function of the RACE,
        /// CLAS and NPC_ records, so writing them would let a save carry a
        /// number a changed load order no longer authors.
        static let actorValues = "AVAL"

        /// Death states (issue #197, roadmap item 15.6): one entry per actor
        /// recorded dead, with the resting root transform its ragdoll settled
        /// at.
        ///
        /// Additive and split out of `RDLT` for the same reason `AVAL` is. A
        /// session in which nothing died writes no chunk at all, so its bytes
        /// match what this encoder produced before the chunk existed.
        ///
        /// The root transform only. Persisting the whole per-bone pose is the
        /// choice item 15.6 declined and documented, so a reloaded corpse lies
        /// where it fell in the skeleton's rest pose rather than in the tangle
        /// it died in (see docs/engine/ragdoll.md).
        static let deaths = "DETH"

        /// Hostility (issue #374, roadmap item 15.7): one entry per actor whose
        /// regard for the player deviates from neutral.
        ///
        /// Additive and split out of `RDLT` for the same reason `AVAL` and
        /// `DETH` are. A session in which nothing was provoked writes no chunk
        /// at all, so its bytes match what this encoder produced before the
        /// chunk existed.
        ///
        /// Hostility only. Whether the *player* is in combat is derived from
        /// which resident actors are hostile and alive, so writing it would let
        /// a save carry a fact that contradicts the world it was loaded into.
        static let combatStates = "CBTS"

        /// Dialogue said-state (issue #426, roadmap item 17.2): one entry per
        /// INFO a speaker has actually said.
        ///
        /// Additive and split out of `RDLT` for the same reason `QSTS` and
        /// `CBTS` are. A session in which nobody spoke writes no chunk at all,
        /// so its bytes match what this encoder produced before the chunk
        /// existed.
        ///
        /// Said-state only. Which topics a speaker offers is a pure function of
        /// the plugin records, the quest state `QSTS` already carries and this
        /// chunk, so writing the offered list would let a save carry a menu a
        /// changed load order no longer authors.
        static let dialogueStates = "DLGS"
    }

    /// Discriminator byte in front of a serialized `ReferenceKey`.
    enum KeyTag {
        static let plugin: UInt8 = 0
        static let generated: UInt8 = 1
    }

    /// Discriminator byte in front of a serialized `CellSceneLocation`.
    enum CellTag {
        static let absent: UInt8 = 0
        static let exterior: UInt8 = 1
        static let interior: UInt8 = 2
    }

    /// Discriminator byte in front of a serialized `PapyrusValue` in `PSCR`.
    ///
    /// Only the five persistable kinds have a tag. `PapyrusValue.object` and
    /// `.array` hold runtime-allocated identity with no world meaning, so the
    /// encoder writes them as `none` rather than inventing a wire shape for a
    /// handle that means nothing after a reload.
    enum ValueTag {
        static let none: UInt8 = 0
        static let boolean: UInt8 = 1
        static let integer: UInt8 = 2
        static let float: UInt8 = 3
        static let string: UInt8 = 4
    }

    /// Bits of a `QSTS` entry's quest-level flag byte. Ours, not Bethesda's:
    /// the DNAM bits a QUST record carries describe what the plugin authored,
    /// while these two describe what the session did.
    enum QuestFlag {
        static let running: UInt8 = 1 << 0
        static let completed: UInt8 = 1 << 1
    }

    /// Bits of a `QSTS` objective's flag byte, in the order the three Papyrus
    /// natives are usually called: displayed, completed, failed.
    enum QuestObjectiveFlag {
        static let displayed: UInt8 = 1 << 0
        static let completed: UInt8 = 1 << 1
        static let failed: UInt8 = 1 << 2
    }

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
}

/// On-disk tag of a component slot inside `RDLT`.
///
/// The mapping is written out case by case rather than derived from
/// `allCases.firstIndex(of:)`, because declaration order is a source-level
/// detail that may change while these byte values may not.
///
/// Optional because not every component slot travels in `RDLT`. `.inventory`,
/// `.spawn`, `.quest`, `.questAliases`, `.actorValues`, `.death`, `.combat` and
/// `.dialogue` have no tag
/// at all: each is carried by its own chunk so that an older build skips it
/// rather than refusing the file (see `ChunkTag.inventories`,
/// `ChunkTag.spawnedReferences`, `ChunkTag.questStates`, `ChunkTag.questAliases`,
/// `ChunkTag.actorValues`, `ChunkTag.deaths`, `ChunkTag.combatStates` and
/// `ChunkTag.dialogueStates`). A nil tag is the encoder's
/// instruction to leave the
/// component out of `RDLT`, and leaving `init?(saveTag:)` without a case for it
/// is what keeps the decoder's "an unknown component kind in `RDLT` is an
/// error" rule intact.
nonisolated extension WorldStateComponentKind {
    var saveTag: UInt8? {
        switch self {
        case .enableState: 0
        case .transform: 1
        case .activation: 2
        case .deletion: 3
        case .inventory, .spawn, .quest, .questAliases, .actorValues, .death,
             .combat, .dialogue: nil
        }
    }

    init?(saveTag: UInt8) {
        switch saveTag {
        case 0: self = .enableState
        case 1: self = .transform
        case 2: self = .activation
        case 3: self = .deletion
        default: return nil
        }
    }
}

/// On-disk tag of a global's declared FNAM type.
///
/// Written out case by case for the same reason component tags are: the FNAM
/// characters are Bethesda's and the byte values here are ours, and neither
/// side should drift when the other changes.
nonisolated extension Global.ValueType {
    var saveTag: UInt8 {
        switch self {
        case .short: 0
        case .long: 1
        case .float: 2
        }
    }

    init?(saveTag: UInt8) {
        switch saveTag {
        case 0: self = .short
        case 1: self = .long
        case 2: self = .float
        default: return nil
        }
    }
}

/// Header metadata describing when and by what a save was written.
///
/// The timestamp is a caller-supplied unix time in seconds rather than
/// something the encoder reads from the clock, because determinism tests must
/// be able to produce the same bytes twice, and because a replayed or migrated
/// save should keep its original creation time.
nonisolated struct SaveCreationMetadata: Equatable, Sendable {
    /// Seconds since the unix epoch, injected by the caller.
    let creationTimestamp: UInt64
    /// Human-readable version of the build that wrote the file.
    let appVersion: String
}

/// One plugin's identity in the load order a save was written against.
///
/// The three stats come straight from the plugin's TES4 HEDR field, which the
/// Creation Kit rewrites whenever the file changes, so together they are a
/// cheap "is this the same plugin as before" check without hashing whole
/// archives. The name is stored with the case it has on disk; comparison is
/// case-insensitive, because the game's original platform treated plugin file
/// names that way and `ReferenceKey` already normalizes to lowercase.
nonisolated struct SavePluginFingerprint: Equatable, Sendable {
    /// Plugin file name, spelled as it appears on disk.
    let name: String
    /// HEDR version float (0.94 / 1.7 / 1.71).
    let hedrVersion: Float
    /// HEDR record + group count.
    let recordCount: Int32
    /// HEDR next object ID.
    let nextObjectID: UInt32

    init(name: String, hedrVersion: Float, recordCount: Int32, nextObjectID: UInt32) {
        self.name = name
        self.hedrVersion = hedrVersion
        self.recordCount = recordCount
        self.nextObjectID = nextObjectID
    }

    init(pluginName: String, stats: PluginHeader.Stats) {
        self.init(
            name: pluginName,
            hedrVersion: stats.version,
            recordCount: stats.recordCount,
            nextObjectID: stats.nextObjectID
        )
    }

    /// Whether two fingerprints name the same plugin, ignoring file-name case.
    func namesSamePlugin(as other: Self) -> Bool {
        name.lowercased() == other.name.lowercased()
    }

    /// Whether the three HEDR stats are identical, which is the "the plugin
    /// has not been edited since the save" test.
    func hasSameStats(as other: Self) -> Bool {
        hedrVersion.bitPattern == other.hedrVersion.bitPattern
            && recordCount == other.recordCount
            && nextObjectID == other.nextObjectID
    }
}
