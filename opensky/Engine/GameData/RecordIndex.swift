// Cross-plugin record headers keyed by load-order-independent identity.
// Plugins and groups are each walked once, lowest priority first. A later
// structurally readable record wins; deleted or unreadable records preserve
// the last valid definition.

import Foundation
import OSLog

nonisolated struct IndexedRecord {
    let record: ESMRecord
    let sourcePlugin: String
    let localized: Bool
}

nonisolated enum RecordIndexResolution: Equatable {
    case nullReference
    case resolved(ResolvedFormID)
    case unavailablePlugin(String)
}

nonisolated enum RecordIndexLookup {
    case record(IndexedRecord)
    case missing(ResolvedFormID)
}

nonisolated enum RecordIndexDecodeResult<Value> {
    case decoded(Value, sourcePlugin: String)
    case missing(ResolvedFormID)
    case undecodable(ResolvedFormID)
}

nonisolated struct RecordIndex {
    /// Reference data loaded once for stores and the Asset Browser. MGEF,
    /// SPEL, SCRL and ENCH join the M18 families because magic links need the
    /// same cross-plugin override semantics and inspector context.
    static let referenceRecordTypes: Set<FourCC> = [
        "KYWD", "FLST", "LCTN", "LCRT", "ECZN", "AACT", "COLL", "DOBJ", "MGEF",
        "SPEL", "SCRL", "ENCH", "SHOU", "WOOP", "LVSP", "DUAL", "EQUP", "AVIF",
        "PERK", "FACT", "RELA", "ASTP"
    ]

    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "RecordIndex"
    )

    private(set) var records: [ResolvedFormID: IndexedRecord] = [:]
    private(set) var collectedRecordCounts: [FourCC: Int] = [:]
    private var candidates: [ResolvedFormID: [IndexedRecord]] = [:]
    private let resolvers: [String: FormIDResolver]
    private let canonicalPluginNames: [String: String]
    private let pluginPriorities: [String: Int]

    init(
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
        for plugin in plugins {
            do {
                decodedResolvers[plugin.name.lowercased()] = try plugin.file
                    .pluginHeader()
                    .formIDResolver(pluginName: plugin.name)
            } catch {
                Self.logger.warning(
                    "Plugin header skipped for \(plugin.name, privacy: .public)"
                )
            }
        }
        resolvers = decodedResolvers

        for plugin in plugins {
            add(pluginName: plugin.name, file: plugin.file, recordTypes: recordTypes)
        }
    }

    func resolve(_ id: FormID, fromPlugin pluginName: String) -> RecordIndexResolution {
        guard let resolver = resolvers[pluginName.lowercased()] else {
            return .unavailablePlugin(pluginName)
        }
        guard let resolved = resolver.resolve(id) else { return .nullReference }
        return .resolved(canonicalize(resolved))
    }

    func lookup(_ id: ResolvedFormID) -> RecordIndexLookup {
        let canonical = canonicalize(id)
        guard let record = records[canonical] else { return .missing(canonical) }
        return .record(record)
    }

    /// Decodes highest priority first, retaining an earlier valid definition
    /// when a later type-specific body is malformed.
    func decode<Value>(
        _ id: ResolvedFormID,
        using decodeRecord: (ESMRecord) throws -> Value
    ) -> RecordIndexDecodeResult<Value> {
        let canonical = canonicalize(id)
        guard let definitions = candidates[canonical] else { return .missing(canonical) }
        for definition in definitions.reversed() {
            if let value = try? decodeRecord(definition.record) {
                return .decoded(value, sourcePlugin: definition.sourcePlugin)
            }
        }
        return .undecodable(canonical)
    }

    /// Variant for decoders that also need owning-plugin metadata such as the
    /// TES4 localized flag. Candidate fallback stays paired with the metadata
    /// of the definition being attempted.
    func decodeIndexed<Value>(
        _ id: ResolvedFormID,
        using decodeRecord: (IndexedRecord) throws -> Value
    ) -> RecordIndexDecodeResult<Value> {
        let canonical = canonicalize(id)
        guard let definitions = candidates[canonical] else { return .missing(canonical) }
        for definition in definitions.reversed() {
            if let value = try? decodeRecord(definition) {
                return .decoded(value, sourcePlugin: definition.sourcePlugin)
            }
        }
        return .undecodable(canonical)
    }

    func count(of type: FourCC) -> Int {
        records.values.count { $0.record.type == type }
    }

    func priority(ofPlugin pluginName: String) -> Int {
        pluginPriorities[pluginName.lowercased()] ?? -1
    }

    /// Structurally readable records seen before override identities collapse.
    func collectedCount(of type: FourCC) -> Int {
        collectedRecordCounts[type, default: 0]
    }

    /// Every structurally readable definition of a type in load order. Most
    /// stores consume only `records`, where overrides collapse by identity;
    /// DOBJ consumes every definition because its overrides merge by tag.
    func definitions(of type: FourCC) -> [IndexedRecord] {
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
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        for group in file.topGroups {
            guard let type = group.recordType, recordTypes.contains(type) else { continue }
            guard let children = try? group.children() else {
                Self.logger.warning(
                    """
                    Malformed \(type.description, privacy: .public) group skipped in \
                    \(pluginName, privacy: .public)
                    """
                )
                continue
            }
            for case let .record(record) in children where !record.isDeleted {
                guard
                    record.type == type,
                    (try? record.fields()) != nil,
                    let resolved = resolver.resolve(FormID(record.formID))
                else { continue }
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

nonisolated enum RecordIndexLoader {
    static func load(
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
