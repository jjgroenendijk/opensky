// On-disk tags for the values that ride inside a chunk (issue #161), split out
// of `OpenSkySaveFormat.swift` when that file reached its size cap.
//
// The split is along a real seam rather than an arbitrary line count.
// `OpenSkySaveFormat` names the file's own vocabulary — the magic, the version,
// the chunk tags and the size bounds. These extensions map *engine* enums onto
// bytes: which component slot travels in `RDLT`, and how a global's declared
// type is spelled. Both are written out case by case rather than derived from
// declaration order, because declaration order is a source-level detail that may
// change while these byte values may not.

import Foundation

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
             .combat, .dialogue, .activeEffects, .spellbook, .enchantedItems, .perks,
             .factions, .playerProgress, .crimeLedger: nil
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
