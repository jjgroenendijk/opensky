// FormID: 32-bit record identifier. Top byte is a mod index into the OWNING
// plugin's master list (TES4 MAST order); low 24 bits identify the object
// inside that plugin. Raw FormIDs are therefore file-relative — the same raw
// value means different things in different plugins, so cross-plugin work
// uses `ResolvedFormID` (plugin name + object ID) instead.
//
// Reference: UESP "Skyrim Mod:FormIDs"
//   https://en.uesp.net/wiki/Skyrim_Mod:FormIDs
// Layout + resolution rules documented in docs/formats/formid.md.

import Foundation

nonisolated public struct FormID: Hashable, Sendable {
    public let rawValue: UInt32

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Index into the owning plugin's master list; values at/above the
    /// master count mean the plugin itself.
    public var masterIndex: Int {
        Int(rawValue >> 24)
    }

    /// Low 24 bits — the object inside its defining plugin.
    public var objectID: UInt32 {
        rawValue & 0x00FF_FFFF
    }

    /// 0x00000000 is the "no reference" sentinel, not a record.
    public var isNull: Bool {
        rawValue == 0
    }
}

nonisolated extension FormID: CustomStringConvertible {
    public var description: String {
        String(format: "%08X", rawValue)
    }
}

/// Load-order-independent record identity: defining plugin + object ID.
nonisolated public struct ResolvedFormID: Hashable, Sendable {
    /// Plugin file name as spelled in the TES4 MAST field (e.g. "Skyrim.esm").
    public let plugin: String
    /// Low 24 bits of the raw FormID.
    public let objectID: UInt32

    public init(plugin: String, objectID: UInt32) {
        self.plugin = plugin
        self.objectID = objectID
    }
}

nonisolated extension ResolvedFormID: CustomStringConvertible {
    public var description: String {
        String(format: "%@:%06X", plugin, objectID)
    }
}

/// Maps raw FormIDs found in one plugin to (plugin, objectID) pairs using
/// that plugin's master list.
nonisolated public struct FormIDResolver: Sendable {
    /// File name of the plugin whose records are being resolved.
    public let pluginName: String
    /// TES4 MAST entries in file order.
    public let masters: [String]

    public init(pluginName: String, masters: [String]) {
        self.pluginName = pluginName
        self.masters = masters
    }

    /// Nil for the null FormID. A master index at/above `masters.count`
    /// resolves to the plugin itself — index == count is the normal encoding
    /// for records the plugin defines; anything higher is clamped the same
    /// way (matches xEdit's handling of malformed plugins).
    public func resolve(_ id: FormID) -> ResolvedFormID? {
        guard !id.isNull else { return nil }
        let plugin = id.masterIndex < masters.count ? masters[id.masterIndex] : pluginName
        return ResolvedFormID(plugin: plugin, objectID: id.objectID)
    }
}
