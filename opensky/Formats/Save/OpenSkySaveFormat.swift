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

    /// Smallest number of bytes a single `RDLT` entry can occupy: a plugin key
    /// with an empty name (1 + 2 + 4), the "no cell" tag (1) and a zero
    /// component count (1). Used to reject an impossible entry count before
    /// any array is reserved.
    static let minimumEntrySize = 9
    /// Smallest number of bytes one fingerprint plugin entry can occupy: an
    /// empty name (2) plus the three stats fields (12).
    static let minimumFingerprintEntrySize = 14
}

/// On-disk tag of a component slot.
///
/// The mapping is written out case by case rather than derived from
/// `allCases.firstIndex(of:)`, because declaration order is a source-level
/// detail that may change while these byte values may not.
nonisolated extension WorldStateComponentKind {
    var saveTag: UInt8 {
        switch self {
        case .enableState: 0
        case .transform: 1
        case .activation: 2
        case .deletion: 3
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
