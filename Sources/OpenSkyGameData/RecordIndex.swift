// Cross-plugin record headers keyed by load-order-independent identity.
// Plugins and groups are each walked once, lowest priority first. A later
// structurally readable record wins; deleted or unreadable records preserve
// the last valid definition.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct IndexedRecord: Sendable {
    public let record: ESMRecord
    public let sourcePlugin: String
    public let localized: Bool
}

nonisolated public enum RecordIndexResolution: Equatable, Sendable {
    case nullReference
    case resolved(ResolvedFormID)
    case unavailablePlugin(String)
}

nonisolated public enum RecordIndexLookup: Sendable {
    case record(IndexedRecord)
    case missing(ResolvedFormID)
}

nonisolated public enum RecordIndexDecodeResult<Value> {
    case decoded(Value, sourcePlugin: String)
    case missing(ResolvedFormID)
    case undecodable(ResolvedFormID, error: any Error)
}

extension RecordIndexDecodeResult: Sendable where Value: Sendable {}

nonisolated public struct RecordIndex: Sendable {
    /// Reference data loaded once for the stores and the Asset Browser.
    public static let referenceRecordTypes: Set<FourCC> = [
        "KYWD", "FLST", "LCTN", "LCRT", "ECZN", "AACT", "COLL", "DOBJ", "MGEF",
        "SPEL", "SCRL", "ENCH", "SHOU", "WOOP", "LVSP", "DUAL", "EQUP", "AVIF",
        "PERK", "FACT", "RELA", "ASTP"
    ]

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "RecordIndex"
    )

    public private(set) var records: [ResolvedFormID: IndexedRecord] = [:]
    public private(set) var collectedRecordCounts: [FourCC: Int] = [:]
    /// Records whose fields do not decode, and malformed groups, by record type.
    public private(set) var skippedRecords = SkippedRecords()
    private var candidates: [ResolvedFormID: [IndexedRecord]] = [:]
    private let resolvers: [String: FormIDResolver]
    private let canonicalPluginNames: [String: String]
    private let pluginPriorities: [String: Int]

    public init(
        plugins: [(name: String, file: ESMFile)],
        recordTypes: Set<FourCC>
    ) {
        canonicalPluginNames = Dictionary(
            plugins.map { ($0.name.lowercased(), $0.name) },
            uniquingKeysWith: { _, later in later }
        )
        pluginPriorities = Dictionary(
            plugins.enumerated().map { ($0.element.name.lowercased(), $0.offset) },
            uniquingKeysWith: { _, later in later }
        )

        var decodedResolvers: [String: FormIDResolver] = [:]
        var skippedHeaders = SkippedRecords()
        for plugin in plugins {
            do {
                decodedResolvers[plugin.name.lowercased()] = try plugin.file
                    .pluginHeader()
                    .formIDResolver(pluginName: plugin.name)
            } catch {
                skippedHeaders.note("TES4", error: error)
                Self.logger.warning(
                    "Plugin header skipped for \(plugin.name, privacy: .public)"
                )
            }
        }
        decodedResolvers[FormIDResolver.loadOrderSpaceName.lowercased()] =
            FormIDResolver.loadOrder(plugins.map(\.name))
        resolvers = decodedResolvers
        skippedRecords = skippedHeaders

        for plugin in plugins {
            add(pluginName: plugin.name, file: plugin.file, recordTypes: recordTypes)
        }
    }

    public func resolve(_ id: FormID, fromPlugin pluginName: String) -> RecordIndexResolution {
        guard let resolver = resolvers[pluginName.lowercased()] else {
            return .unavailablePlugin(pluginName)
        }
        guard let resolved = resolver.resolve(id) else { return .nullReference }
        return .resolved(canonicalize(resolved))
    }

    public func lookup(_ id: ResolvedFormID) -> RecordIndexLookup {
        let canonical = canonicalize(id)
        guard let record = records[canonical] else { return .missing(canonical) }
        return .record(record)
    }

    /// Decodes highest priority first, keeping an earlier valid definition when
    /// a later body is malformed. `.undecodable` carries the winner's error.
    public func decode<Value>(
        _ id: ResolvedFormID,
        using decodeRecord: (ESMRecord) throws -> Value
    ) -> RecordIndexDecodeResult<Value> {
        decodeIndexed(id) { try decodeRecord($0.record) }
    }

    /// Variant for decoders that also need the owning plugin's metadata, such as
    /// the TES4 localized flag.
    public func decodeIndexed<Value>(
        _ id: ResolvedFormID,
        using decodeRecord: (IndexedRecord) throws -> Value
    ) -> RecordIndexDecodeResult<Value> {
        let canonical = canonicalize(id)
        guard let definitions = candidates[canonical] else { return .missing(canonical) }
        var firstError: (any Error)?
        for definition in definitions.reversed() {
            do {
                let value = try decodeRecord(definition)
                return .decoded(value, sourcePlugin: definition.sourcePlugin)
            } catch {
                firstError = firstError ?? error
            }
        }
        return .undecodable(canonical, error: firstError ?? ESMError.malformed("no definition"))
    }

    /// Winning identities of `types`, lowest plugin priority first, so the last
    /// write into an editor-ID map is the definition the load order prefers.
    public func orderedRecordIDs(of types: Set<FourCC>) -> [ResolvedFormID] {
        records.keys
            .filter { records[$0].map { types.contains($0.record.type) } ?? false }
            .sorted { RecordStoreOrdering.precedes($0, $1, index: self) }
    }

    /// The master list of a loaded plugin, or nil for a plugin not in the index.
    public func resolver(ofPlugin pluginName: String) -> FormIDResolver? {
        resolvers[pluginName.lowercased()]
    }

    public func resolvedID(_ id: FormID?, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard let id, case let .resolved(resolved) = resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolved
    }

    public func count(of type: FourCC) -> Int {
        records.values.count { $0.record.type == type }
    }

    public func priority(ofPlugin pluginName: String) -> Int {
        pluginPriorities[pluginName.lowercased()] ?? -1
    }

    /// Structurally readable records seen before override identities collapse.
    public func collectedCount(of type: FourCC) -> Int {
        collectedRecordCounts[type, default: 0]
    }

    /// Every structurally readable definition of a type in load order. Most
    /// stores consume only `records`, where overrides collapse by identity;
    /// DOBJ consumes every definition because its overrides merge by tag.
    public func definitions(of type: FourCC) -> [IndexedRecord] {
        candidates.values
            .flatMap(\.self)
            .filter { $0.record.type == type }
            .sorted { left, right in
                let leftPriority = priority(ofPlugin: left.sourcePlugin)
                let rightPriority = priority(ofPlugin: right.sourcePlugin)
                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }
                return left.record.formID < right.record.formID
            }
    }

    private mutating func add(
        pluginName: String,
        file: ESMFile,
        recordTypes: Set<FourCC>
    ) {
        guard let resolver = resolvers[pluginName.lowercased()] else { return }
        let localized = file.isLocalized
        for group in file.topGroups {
            guard let type = group.recordType, recordTypes.contains(type) else { continue }
            for case let .record(record) in skippedRecords.children(of: group)
                where !record.isDeleted && record.type == type
            {
                do {
                    _ = try record.fields()
                } catch {
                    skippedRecords.note(type, error: error)
                    continue
                }
                guard let resolved = resolver.resolve(FormID(record.formID)) else { continue }
                collectedRecordCounts[type, default: 0] += 1
                let canonical = canonicalize(resolved)
                let entry = IndexedRecord(
                    record: record,
                    sourcePlugin: pluginName,
                    localized: localized
                )
                candidates[canonical, default: []].append(entry)
                records[canonical] = entry
            }
        }
    }

    private func canonicalize(_ id: ResolvedFormID) -> ResolvedFormID {
        ResolvedFormID(
            plugin: canonicalPluginNames[id.plugin.lowercased()] ?? id.plugin,
            objectID: id.objectID
        )
    }
}

nonisolated public enum RecordIndexLoader: Sendable {
    public static func load(
        root: GameDataRoot,
        baseFile: ESMFile? = nil,
        recordTypes: Set<FourCC> = RecordIndex.referenceRecordTypes
    ) -> RecordIndex {
        RecordIndex(
            plugins: ActivePluginFiles.load(root: root, baseFile: baseFile),
            recordTypes: recordTypes
        )
    }
}
