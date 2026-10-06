// FormID: the top byte indexes the owning plugin's master list, the low 24
// bits name the object. A raw FormID is file-relative, so cross-plugin work
// uses `ResolvedFormID`. Rules: docs/formats/formid.md.

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
nonisolated public struct FormIDResolver: Equatable, Sendable {
    /// File name of the plugin whose records are being resolved.
    public let pluginName: String
    /// TES4 MAST entries in file order.
    public let masters: [String]

    public init(pluginName: String, masters: [String]) {
        self.pluginName = pluginName
        self.masters = masters
    }

    /// The FormID space of a whole load order: the top byte is the plugin's
    /// position, as the game numbers forms at runtime. The first plugin, `Skyrim.esm`,
    /// is 0, so its own FormIDs keep their value.
    public static func loadOrder(_ plugins: [String]) -> FormIDResolver {
        FormIDResolver(pluginName: plugins.last ?? "", masters: Array(plugins.dropLast()))
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

    /// The raw FormID this plugin writes for `id`, or nil when `id` lives in a
    /// plugin this one does not list. Plugin names compare without case.
    public func localFormID(of id: ResolvedFormID) -> FormID? {
        let name = id.plugin.lowercased()
        let index = name == pluginName.lowercased()
            ? masters.count
            : masters.firstIndex { $0.lowercased() == name }
        guard let index, index < 0xFF, id.objectID <= 0xFFFFFF else { return nil }
        return FormID(UInt32(index) << 24 | id.objectID)
    }
}

/// Rewrites FormIDs written in one plugin into another FormID space, such as the
/// load order. A form the target space cannot name becomes the null FormID.
nonisolated public struct FormIDTranslation: Equatable, Sendable {
    public let source: FormIDResolver
    public let target: FormIDResolver

    public init(source: FormIDResolver, target: FormIDResolver) {
        self.source = source
        self.target = target
    }

    public func callAsFunction(_ id: FormID) -> FormID {
        guard let resolved = source.resolve(id) else { return id }
        return target.localFormID(of: resolved) ?? FormID(0)
    }

    public func callAsFunction(_ id: FormID?) -> FormID? {
        id.map { self($0) }
    }
}
