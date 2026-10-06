// Maps the save's form references onto the load order installed now. A runtime form id
// in the save names a plugin by its position in the save's own lists, so it is read
// through those lists first. See docs/formats/ess.md#ref-ids.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsESS

/// Why a form reference in a save has no meaning in the current load order.
nonisolated public enum ESSUnmappedReason: Hashable, Sendable {
    case pluginNotLoaded(String)
    case pluginIndexOutOfRange(Int)
    case lightPluginIndexOutOfRange(Int)
    case formIDArrayIndexOutOfRange(UInt32)
    case unknownRefIDKind

    public var description: String {
        switch self {
        case let .pluginNotLoaded(name): "plugin \(name) is not loaded"
        case let .pluginIndexOutOfRange(index): "plugin index \(index) is past the save's list"
        case let .lightPluginIndexOutOfRange(index):
            "light plugin index \(index) is past the save's list"
        case let .formIDArrayIndexOutOfRange(index): "form id array index \(index) is out of range"
        case .unknownRefIDKind: "ref id kind 3 is undocumented"
        }
    }
}

nonisolated public enum ESSFormResolution: Hashable, Sendable {
    case null
    /// A form a plugin defines, by plugin name as the save spells it.
    case form(ResolvedFormID)
    /// A form the game created, by its low 24 bits.
    case created(UInt32)
    case unmapped(ESSUnmappedReason)
}

nonisolated public struct ESSLoadOrderMapping: Sendable {
    public let savePlugins: [String]
    public let saveLightPlugins: [String]
    public let formIDArray: [UInt32]
    /// The plugins loaded now, in load order.
    public let currentPlugins: [String]
    private let loaded: Set<String>
    private let currentResolver: FormIDResolver

    public init(file: ESSFile, currentPlugins: [String]) {
        savePlugins = file.plugins
        saveLightPlugins = file.lightPlugins
        formIDArray = file.formIDArray
        self.currentPlugins = currentPlugins
        loaded = Set(currentPlugins.map { $0.lowercased() })
        currentResolver = FormIDResolver.loadOrder(currentPlugins)
    }

    public func resolve(_ ref: ESSRefID) -> ESSFormResolution {
        if ref.isNull {
            return .null
        }
        switch ref.kind {
        case .formIDArray:
            guard let id = ref.formID(in: formIDArray) else {
                return .unmapped(.formIDArrayIndexOutOfRange(ref.value))
            }
            return resolve(runtimeFormID: id)
        case .default, .created:
            return resolve(runtimeFormID: ref.formID(in: formIDArray) ?? 0)
        case .unknown:
            return .unmapped(.unknownRefIDKind)
        }
    }

    /// A form id in the save's load order: top byte a plugin index, `0xFE` a light
    /// plugin with a 12-bit index and a 12-bit object id, `0xFF` a created form.
    public func resolve(runtimeFormID id: UInt32) -> ESSFormResolution {
        guard id != 0 else { return .null }
        let top = Int(id >> 24)
        switch top {
        case 0xFF:
            return .created(id & 0x00FF_FFFF)
        case 0xFE:
            let index = Int(id >> 12 & 0xFFF)
            guard index < saveLightPlugins.count else {
                return .unmapped(.lightPluginIndexOutOfRange(index))
            }
            return checked(ResolvedFormID(plugin: saveLightPlugins[index], objectID: id & 0xFFF))
        default:
            guard top < savePlugins.count else { return .unmapped(.pluginIndexOutOfRange(top)) }
            return checked(ResolvedFormID(plugin: savePlugins[top], objectID: id & 0x00FF_FFFF))
        }
    }

    private func checked(_ form: ResolvedFormID) -> ESSFormResolution {
        loaded.contains(form.plugin.lowercased())
            ? .form(form) : .unmapped(.pluginNotLoaded(form.plugin))
    }

    /// The form id in the current load-order space, as record stores number forms.
    public func currentFormID(_ form: ResolvedFormID) -> FormID? {
        currentResolver.localFormID(of: form)
    }

    public var comparison: ESSLoadOrderComparison {
        ESSLoadOrderComparison(
            savePlugins: savePlugins + saveLightPlugins, currentPlugins: currentPlugins
        )
    }
}

/// The save's plugins against the ones loaded now.
nonisolated public struct ESSLoadOrderComparison: Equatable, Sendable {
    nonisolated public struct Row: Equatable, Sendable {
        public let name: String
        public let savePosition: Int
        /// Nil when the plugin is not loaded now.
        public let currentPosition: Int?
    }

    public let rows: [Row]
    /// Loaded now but absent from the save.
    public let added: [String]

    public init(savePlugins: [String], currentPlugins: [String]) {
        var positions: [String: Int] = [:]
        for (index, name) in currentPlugins.enumerated() {
            positions[name.lowercased()] = positions[name.lowercased()] ?? index
        }
        rows = savePlugins.enumerated().map { index, name in
            Row(name: name, savePosition: index, currentPosition: positions[name.lowercased()])
        }
        let saved = Set(savePlugins.map { $0.lowercased() })
        added = currentPlugins.filter { !saved.contains($0.lowercased()) }
    }

    public var missing: [String] {
        rows.filter { $0.currentPosition == nil }.map(\.name)
    }

    /// True when the plugins both lists hold appear in a different relative order.
    public var isReordered: Bool {
        let order = rows.compactMap(\.currentPosition)
        return order != order.sorted()
    }
}
