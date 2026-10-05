// Load-order-wide FLST lookup, nesting expansion and membership queries above
// RecordIndex. Overrides replace whole lists; entries never append across
// plugin definitions.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedFormList: Equatable, Sendable {
    public let id: ResolvedFormID
    public let list: FormList
    public let sourcePlugin: String
}

nonisolated public struct FlattenedFormList: Equatable, Sendable {
    /// Leaf entries in list order. Nil preserves a legal null FLST element.
    public let entries: [ResolvedFormID?]
    /// Deepest list level expanded, where the requested list is depth zero.
    public let maximumDepth: Int
    public let hitDepthCap: Bool
}

nonisolated public struct FormListStore: Sendable {
    /// Higher than the measured vanilla maximum while still bounding hostile
    /// acyclic mods. A branch at the cap is omitted and logged.
    public static let depthCap = 32

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "FormListStore"
    )

    private let index: RecordIndex
    private let table: ResolvedRecordTable<ResolvedFormList>

    public var formLists: [ResolvedFormID: ResolvedFormList] {
        table.values
    }

    public var skippedRecords: SkippedRecords {
        table.skipped
    }

    public init(index: RecordIndex) {
        self.index = index
        table = ResolvedRecordTable(
            index: index,
            types: ["FLST"],
            decode: { try FormList(record: $0.record) },
            editorID: \.editorID,
            resolve: { ResolvedFormList(id: $0, list: $1, sourcePlugin: $2) }
        )
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(
            plugins: plugins,
            recordTypes: RecordIndex.referenceRecordTypes
        ))
    }

    public func formList(_ id: ResolvedFormID) -> ResolvedFormList? {
        table.value(id)
    }

    public func formList(editorID: String) -> ResolvedFormList? {
        table.value(editorID: editorID)
    }

    public func resolvedID(_ entry: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        index.resolvedID(entry, fromPlugin: pluginName)
    }

    public func flattened(_ id: ResolvedFormID) -> FlattenedFormList? {
        guard let root = formList(id) else { return nil }
        var state = FlattenState()
        var active = Set([root.id])
        flatten(root, depth: 0, active: &active, state: &state)
        return FlattenedFormList(
            entries: state.entries,
            maximumDepth: state.maximumDepth,
            hitDepthCap: state.hitDepthCap
        )
    }

    public func contains(_ member: ResolvedFormID, in listID: ResolvedFormID) -> Bool {
        flattened(listID)?.entries.contains { $0 == member } ?? false
    }

    /// Human-readable raw-list entry for `RecordTextDump`. FLST, KYWD and AACT
    /// entries show their editor ID; other identities show the FormID.
    public func displayString(for entry: FormID?, fromPlugin pluginName: String) -> String {
        guard let entry else { return "NULL" }
        guard case let .resolved(id) = index.resolve(entry, fromPlugin: pluginName) else {
            return "[UNRESOLVED] \(entry)"
        }
        guard case let .record(indexed) = index.lookup(id) else {
            return "[UNRESOLVED] \(id)"
        }
        let editorID: String? = switch indexed.record.type {
        case "FLST", "KYWD", "AACT": ESMWalk.editorID(of: indexed.record)
        default: nil
        }
        return editorID ?? id.description
    }

    private func flatten(
        _ resolved: ResolvedFormList,
        depth: Int,
        active: inout Set<ResolvedFormID>,
        state: inout FlattenState
    ) {
        state.maximumDepth = max(state.maximumDepth, depth)
        for entry in resolved.list.entries {
            guard let entry else {
                state.entries.append(nil)
                continue
            }
            guard
                case let .resolved(id) = index.resolve(
                    entry,
                    fromPlugin: resolved.sourcePlugin
                )
            else { continue }
            guard let nested = formList(id) else {
                state.entries.append(id)
                continue
            }
            guard !active.contains(nested.id) else { continue }
            guard depth < Self.depthCap else {
                state.hitDepthCap = true
                Self.logger.warning(
                    "FLST depth cap hit at \(nested.id.description, privacy: .public)"
                )
                continue
            }
            active.insert(nested.id)
            flatten(nested, depth: depth + 1, active: &active, state: &state)
            active.remove(nested.id)
        }
    }
}

nonisolated private struct FlattenState {
    var entries: [ResolvedFormID?] = []
    var maximumDepth = 0
    var hitDepthCap = false
}
