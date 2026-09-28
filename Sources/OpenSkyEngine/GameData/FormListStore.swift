// Load-order-wide FLST lookup, nesting expansion and membership queries above
// RecordIndex. Overrides replace whole lists; entries never append across
// plugin definitions.

import Foundation
import OSLog

nonisolated struct ResolvedFormList: Equatable {
    let id: ResolvedFormID
    let list: FormList
    let sourcePlugin: String
}

nonisolated struct FlattenedFormList: Equatable {
    /// Leaf entries in list order. Nil preserves a legal null FLST element.
    let entries: [ResolvedFormID?]
    /// Deepest list level expanded, where the requested list is depth zero.
    let maximumDepth: Int
    let hitDepthCap: Bool
}

nonisolated struct FormListStore {
    /// Higher than the measured vanilla maximum while still bounding hostile
    /// acyclic mods. A branch at the cap is omitted and logged.
    static let depthCap = 32

    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "FormListStore"
    )

    private let index: RecordIndex
    private(set) var formLists: [ResolvedFormID: ResolvedFormList] = [:]
    private var formListsByEditorID: [String: ResolvedFormList] = [:]

    init(index: RecordIndex) {
        self.index = index
        let orderedIDs = index.records.keys.sorted {
            Self.precedes($0, $1, index: index)
        }
        for id in orderedIDs {
            guard index.records[id]?.record.type == "FLST" else { continue }
            guard
                case let .decoded(list, sourcePlugin) = index.decode(
                    id,
                    using: FormList.init(record:)
                )
            else { continue }
            let resolved = ResolvedFormList(id: id, list: list, sourcePlugin: sourcePlugin)
            formLists[id] = resolved
            if let editorID = list.editorID {
                formListsByEditorID[editorID.lowercased()] = resolved
            }
        }
    }

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(
            plugins: plugins,
            recordTypes: RecordIndex.referenceRecordTypes
        ))
    }

    func formList(_ id: ResolvedFormID) -> ResolvedFormList? {
        formLists[id] ?? formLists.first { key, _ in
            key.objectID == id.objectID
                && key.plugin.caseInsensitiveCompare(id.plugin) == .orderedSame
        }?.value
    }

    func formList(editorID: String) -> ResolvedFormList? {
        formListsByEditorID[editorID.lowercased()]
    }

    func resolvedID(_ entry: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(id) = index.resolve(entry, fromPlugin: pluginName) else {
            return nil
        }
        return id
    }

    func flattened(_ id: ResolvedFormID) -> FlattenedFormList? {
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

    func contains(_ member: ResolvedFormID, in listID: ResolvedFormID) -> Bool {
        flattened(listID)?.entries.contains { $0 == member } ?? false
    }

    /// Human-readable raw-list entry for `RecordTextDump`. Only record types
    /// decoded in M18 are named; other resolved identities remain explicit.
    func displayString(for entry: FormID?, fromPlugin pluginName: String) -> String {
        guard let entry else { return "NULL" }
        guard case let .resolved(id) = index.resolve(entry, fromPlugin: pluginName) else {
            return "[UNRESOLVED] \(entry)"
        }
        guard case let .record(indexed) = index.lookup(id) else {
            return "[UNRESOLVED] \(id)"
        }
        let editorID: String? = switch indexed.record.type {
        case "FLST": (try? FormList(record: indexed.record))?.editorID
        case "KYWD": (try? Keyword(record: indexed.record))?.editorID
        case "AACT": (try? ActionRecord(record: indexed.record))?.editorID
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

    private static func precedes(
        _ left: ResolvedFormID,
        _ right: ResolvedFormID,
        index: RecordIndex
    ) -> Bool {
        let leftSource = index.records[left]?.sourcePlugin ?? left.plugin
        let rightSource = index.records[right]?.sourcePlugin ?? right.plugin
        let leftPriority = index.priority(ofPlugin: leftSource)
        let rightPriority = index.priority(ofPlugin: rightSource)
        if leftPriority != rightPriority {
            return leftPriority < rightPriority
        }
        if left.plugin.caseInsensitiveCompare(right.plugin) != .orderedSame {
            return left.plugin.localizedCaseInsensitiveCompare(right.plugin) == .orderedAscending
        }
        return left.objectID < right.objectID
    }
}

nonisolated private struct FlattenState {
    var entries: [ResolvedFormID?] = []
    var maximumDepth = 0
    var hitDepthCap = false
}

nonisolated enum FormListStoreLoader {
    static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> FormListStore {
        FormListStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
