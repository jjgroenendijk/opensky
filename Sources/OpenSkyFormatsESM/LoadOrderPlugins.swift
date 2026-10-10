// Every active plugin, read as one load order. A store walks a record type
// across all plugins, lowest priority first, and the last plugin that has a
// record wins. Records decode straight into the load-order FormID space
// (`RecordDecodeScope`). Rules: docs/formats/formid.md#load-order-space.

import Foundation
import OpenSkyFormatsCore

/// One active plugin and the translation of its FormIDs into the load-order space.
nonisolated public struct LoadOrderPlugin: Sendable {
    public let name: String
    public let file: ESMFile
    /// 0 is the first plugin, normally `Skyrim.esm`.
    public let position: Int
    public let translation: FormIDTranslation

    public var localized: Bool {
        file.isLocalized
    }

    /// The load-order FormID of a record this plugin holds.
    public func formID(of record: ESMRecord) -> FormID {
        translation(FormID(stored: record.formID))
    }

    /// Runs a decode of this plugin's records in the load-order space. A table ID
    /// of a later plugin remembers the plugin, because its string tables hold the text.
    public func decode<Value>(_ body: () throws -> Value) rethrows -> Value {
        try RecordDecodeScope.decoding(
            translation: translation, stringPlugin: position > 0 ? name : nil, body
        )
    }
}

/// One plugin's record, decoded on demand into the load-order space.
nonisolated public struct LoadOrderRecord: Sendable {
    public let record: ESMRecord
    public let plugin: LoadOrderPlugin

    public var position: Int {
        plugin.position
    }

    public var localized: Bool {
        plugin.localized
    }

    /// The record's own FormID in the load-order space.
    public var formID: FormID {
        plugin.formID(of: record)
    }

    public func decode<Value>(_ decode: (ESMRecord) throws -> Value) rethrows -> Value {
        try plugin.decode { try decode(record) }
    }
}

nonisolated public struct LoadOrderPlugins: Sendable {
    /// The FormID space every value is numbered in.
    public let space: FormIDResolver
    /// Lowest priority first.
    public let plugins: [LoadOrderPlugin]

    /// - Parameter space: the target space. Nil picks the load order of
    ///   `plugins`, or for one plugin its own space, so nothing moves.
    public init(_ plugins: [(name: String, file: ESMFile)], space: FormIDResolver? = nil) {
        var skipped = SkippedRecords()
        let resolvers = plugins.map {
            FormIDResolver(pluginName: $0.name, masters: skipped.masters(of: $0.file))
        }
        let space = space ?? (plugins.count == 1
            ? resolvers[0] : FormIDResolver.loadOrder(plugins.map(\.name)))
        self.space = space
        self.plugins = zip(plugins, resolvers).enumerated().map { position, pair in
            LoadOrderPlugin(
                name: pair.0.name,
                file: pair.0.file,
                position: position,
                translation: FormIDTranslation(source: pair.1, target: space)
            )
        }
    }

    /// The plugins as the stores that take a plain list read them.
    public var files: [(name: String, file: ESMFile)] {
        plugins.map { ($0.name, $0.file) }
    }

    /// One plugin in its own FormID space. The name only keys `GlobalStore` keys.
    public init(file: ESMFile, name: String = "") {
        self.init([(name, file)])
    }

    /// Decoded `type` records in first-seen order. A later record that does not
    /// decode keeps the earlier version.
    public func decodeRecords<Value>(
        of type: FourCC,
        skipped: inout SkippedRecords,
        using decode: (ESMRecord) throws -> Value?
    ) -> [Value] {
        decodeRecords(of: type, skipped: &skipped, using: { (record: ESMRecord, _: Bool) in
            try decode(record)
        })
    }

    /// The same, for a decoder that needs the TES4 localized flag of the record's plugin.
    public func decodeRecords<Value>(
        of type: FourCC,
        skipped: inout SkippedRecords,
        using decode: (ESMRecord, Bool) throws -> Value?
    ) -> [Value] {
        let decoded = decodedRecords(of: type, skipped: &skipped) { try decode($0, $1.localized) }
        return decoded.order.compactMap { decoded.values[$0] }
    }

    /// Decoded `type` records keyed by load-order FormID.
    public func indexRecords<Value>(
        of type: FourCC,
        skipped: inout SkippedRecords,
        using decode: (ESMRecord) throws -> Value?
    ) -> [UInt32: Value] {
        indexRecords(of: type, skipped: &skipped, using: { (record: ESMRecord, _: Bool) in
            try decode(record)
        })
    }

    public func indexRecords<Value>(
        of type: FourCC,
        skipped: inout SkippedRecords,
        using decode: (ESMRecord, Bool) throws -> Value?
    ) -> [UInt32: Value] {
        indexPluginRecords(of: type, skipped: &skipped) { try decode($0, $1.localized) }
    }

    /// The same, for a decoder that keeps the plugin, such as its `translation`
    /// for conditions, which stay as written.
    public func indexPluginRecords<Value>(
        of type: FourCC,
        skipped: inout SkippedRecords,
        using decode: (ESMRecord, LoadOrderPlugin) throws -> Value?
    ) -> [UInt32: Value] {
        let decoded = decodedRecords(of: type, skipped: &skipped, using: decode)
        return Dictionary(uniqueKeysWithValues: decoded.values.map { ($0.key.rawValue, $0.value) })
    }

    private func decodedRecords<Value>(
        of type: FourCC,
        skipped: inout SkippedRecords,
        using decode: (ESMRecord, LoadOrderPlugin) throws -> Value?
    ) -> (order: [FormID], values: [FormID: Value]) {
        var order: [FormID] = []
        var values: [FormID: Value] = [:]
        for plugin in plugins {
            for record in plugin.file.liveRecords(of: type, skipped: &skipped) {
                let id = plugin.formID(of: record)
                let value: Value?
                do {
                    value = try plugin.decode { try decode(record, plugin) }
                } catch {
                    skipped.note(type, error: error)
                    continue
                }
                guard let value else { continue }
                if values.updateValue(value, forKey: id) == nil {
                    order.append(id)
                }
            }
        }
        return (order, values)
    }
}
