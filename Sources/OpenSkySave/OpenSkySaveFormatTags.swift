// On-disk tags for engine enums inside a chunk: component slots in `RDLT` and global
// types. Written case by case, because declaration order may change but bytes may not.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

/// On-disk tag of a component slot inside `RDLT`, written case by case. Nil for slots
/// carried by their own chunk (inventory, spawn, quests, actor values, death, combat,
/// dialogue): the encoder leaves them out, and the decoder still errors on unknown kinds.
nonisolated extension WorldStateComponentKind {
    public var saveTag: UInt8? {
        switch self {
        case .enableState: 0
        case .transform: 1
        case .activation: 2
        case .deletion: 3
        default: nil
        }
    }

    public init?(saveTag: UInt8) {
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
    public var saveTag: UInt8 {
        switch self {
        case .short: 0
        case .long: 1
        case .float: 2
        }
    }

    public init?(saveTag: UInt8) {
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
nonisolated public struct SaveCreationMetadata: Equatable, Sendable {
    /// Seconds since the unix epoch, injected by the caller.
    public let creationTimestamp: UInt64
    /// Human-readable version of the build that wrote the file.
    public let appVersion: String

    public init(creationTimestamp: UInt64, appVersion: String) {
        self.creationTimestamp = creationTimestamp
        self.appVersion = appVersion
    }
}

/// One plugin in the saved load order. The TES4 HEDR stats change whenever the file
/// changes, so they are a cheap identity check. The name keeps its case; comparison ignores it.
nonisolated public struct SavePluginFingerprint: Equatable, Sendable {
    /// Plugin file name, spelled as it appears on disk.
    public let name: String
    /// HEDR version float (0.94 / 1.7 / 1.71).
    public let hedrVersion: Float
    /// HEDR record + group count.
    public let recordCount: Int32
    /// HEDR next object ID.
    public let nextObjectID: UInt32

    public init(name: String, hedrVersion: Float, recordCount: Int32, nextObjectID: UInt32) {
        self.name = name
        self.hedrVersion = hedrVersion
        self.recordCount = recordCount
        self.nextObjectID = nextObjectID
    }

    public init(pluginName: String, stats: PluginHeader.Stats) {
        self.init(
            name: pluginName,
            hedrVersion: stats.version,
            recordCount: stats.recordCount,
            nextObjectID: stats.nextObjectID
        )
    }

    /// Whether two fingerprints name the same plugin, ignoring file-name case.
    public func namesSamePlugin(as other: Self) -> Bool {
        name.lowercased() == other.name.lowercased()
    }

    /// Whether the three HEDR stats are identical, which is the "the plugin
    /// has not been edited since the save" test.
    public func hasSameStats(as other: Self) -> Bool {
        hedrVersion.bitPattern == other.hedrVersion.bitPattern
            && recordCount == other.recordCount
            && nextObjectID == other.nextObjectID
    }
}
