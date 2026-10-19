// FormID: the top byte indexes the owning plugin's master list, the low 24
// bits name the object. A raw FormID is file-relative, so cross-plugin work
// uses `ResolvedFormID`. Rules: docs/formats/formid.md.

import Foundation

nonisolated public struct FormID: Hashable, Sendable {
    public let rawValue: UInt32

    /// Inside `RecordDecodeScope.decoding`, the value moves into the scope's
    /// FormID space, so a decoder reads every FormID of a record translated.
    public init(_ rawValue: UInt32) {
        self.rawValue = RecordDecodeScope.translated(rawValue)
    }

    /// The value as written; a decode scope leaves it alone.
    public init(stored rawValue: UInt32) {
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
    /// The light plugins of a load-order space, in slot order. They share the
    /// `0xFE` top byte: `FE xxx yyy`, slot `xxx`, object `yyy`.
    public let lightPlugins: [String]

    public init(pluginName: String, masters: [String], lightPlugins: [String] = []) {
        self.pluginName = pluginName
        self.masters = masters
        self.lightPlugins = lightPlugins
    }

    /// The top byte every light plugin shares at runtime.
    public static let lightTopByte = 0xFE
    /// The largest object ID a light plugin can hold.
    public static let lightObjectIDMask: UInt32 = 0xFFF

    /// The name a store registers the load-order space under, so a FormID read
    /// in that space resolves like one read in a plugin. No file has this name.
    public static let loadOrderSpaceName = "<load order>"

    /// The FormID space of a whole load order, as the game numbers forms at runtime.
    /// A full plugin's top byte is its position among full plugins, so `Skyrim.esm`
    /// keeps its values. A plugin named in `light` takes a `0xFE` slot.
    public static func loadOrder(_ plugins: [String], light: Set<String> = []) -> FormIDResolver {
        let light = Set(light.map { $0.lowercased() })
        let isLight = { (name: String) in light.contains(name.lowercased()) }
        let full = plugins.filter { !isLight($0) }
        return FormIDResolver(
            pluginName: full.last ?? "",
            masters: Array(full.dropLast()),
            lightPlugins: plugins.filter(isLight)
        )
    }

    /// The load-order space of opened plugins; each one's TES4 flags or `.esl`
    /// extension marks it light.
    public static func loadOrder(files plugins: [(name: String, file: ESMFile)]) -> FormIDResolver {
        loadOrder(
            plugins.map(\.name),
            light: Set(plugins.filter { $0.file.isLight(named: $0.name) }
                .map { $0.name.lowercased() })
        )
    }

    /// Nil for the null FormID. A master index at/above `masters.count`
    /// resolves to the plugin itself — index == count is the normal encoding
    /// for records the plugin defines; anything higher is clamped the same
    /// way (matches xEdit's handling of malformed plugins).
    public func resolve(_ id: FormID) -> ResolvedFormID? {
        guard !id.isNull else { return nil }
        if !lightPlugins.isEmpty, id.masterIndex == Self.lightTopByte {
            let slot = Int(id.rawValue >> 12 & Self.lightObjectIDMask)
            guard slot < lightPlugins.count else { return nil }
            return ResolvedFormID(
                plugin: lightPlugins[slot], objectID: id.rawValue & Self.lightObjectIDMask
            )
        }
        let plugin = id.masterIndex < masters.count ? masters[id.masterIndex] : pluginName
        return ResolvedFormID(plugin: plugin, objectID: id.objectID)
    }

    /// The raw FormID this plugin writes for `id`, or nil when `id` lives in a
    /// plugin this one does not list. Plugin names compare without case.
    public func localFormID(of id: ResolvedFormID) -> FormID? {
        let name = id.plugin.lowercased()
        if let slot = lightPlugins.firstIndex(where: { $0.lowercased() == name }) {
            guard id.objectID <= Self.lightObjectIDMask else { return nil }
            return FormID(
                stored: UInt32(Self.lightTopByte) << 24 | UInt32(slot) << 12 | id.objectID
            )
        }
        let index = name == pluginName.lowercased()
            ? masters.count
            : masters.firstIndex { $0.lowercased() == name }
        let limit = lightPlugins.isEmpty ? 0xFF : Self.lightTopByte
        guard let index, index < limit, id.objectID <= 0xFFFFFF else { return nil }
        return FormID(stored: UInt32(index) << 24 | id.objectID)
    }
}

/// Rewrites FormIDs written in one plugin into another FormID space, such as the
/// load order. A form the target space cannot name becomes the null FormID.
nonisolated public struct FormIDTranslation: Equatable, Sendable {
    public let source: FormIDResolver
    public let target: FormIDResolver
    /// True when every FormID keeps its value: the source lists its masters in
    /// the target's order and sits right after them.
    public let isIdentity: Bool
    /// The target prefix for each source top byte; nil where the target space
    /// cannot name the plugin.
    private let prefixes: [Prefix?]

    /// The high bits a target FormID starts with, and the object ID bits it keeps.
    private struct Prefix: Equatable {
        let base: UInt32
        let objectMask: UInt32
    }

    public init(source: FormIDResolver, target: FormIDResolver) {
        self.source = source
        self.target = target
        prefixes = (0 ... 0xFF).map { index in
            let plugin = index < source.masters.count ? source.masters[index] : source.pluginName
            guard
                let base = target.localFormID(of: ResolvedFormID(plugin: plugin, objectID: 0))
            else { return nil }
            let isLight = !target.lightPlugins.isEmpty
                && base.masterIndex == FormIDResolver.lightTopByte
            return Prefix(
                base: base.rawValue,
                objectMask: isLight ? FormIDResolver.lightObjectIDMask : 0x00FF_FFFF
            )
        }
        isIdentity = source.lightPlugins == target.lightPlugins
            && prefixes.enumerated().allSatisfy { index, prefix in
                index > source.masters.count
                    || prefix == Prefix(base: UInt32(index) << 24, objectMask: 0x00FF_FFFF)
            }
    }

    public func callAsFunction(_ id: FormID) -> FormID {
        FormID(stored: translate(id.rawValue))
    }

    /// The null FormID stays null. An object ID too large for a light slot
    /// becomes null too, since the slot cannot name it.
    func translate(_ raw: UInt32) -> UInt32 {
        guard raw != 0 else { return 0 }
        let top = Int(raw >> 24)
        if top == FormIDResolver.lightTopByte, !source.lightPlugins.isEmpty {
            return source.resolve(FormID(stored: raw))
                .flatMap { target.localFormID(of: $0)?.rawValue } ?? 0
        }
        guard let prefix = prefixes[top] else { return 0 }
        let object = raw & 0x00FF_FFFF
        guard object & ~prefix.objectMask == 0 else { return 0 }
        return prefix.base | object
    }

    public func callAsFunction(_ id: FormID?) -> FormID? {
        id.map { self($0) }
    }
}
