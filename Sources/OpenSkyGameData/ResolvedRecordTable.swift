// The shared build of a load-order-wide record store over `RecordIndex`: walk
// the winning identities in load order, keep the chosen types, decode, count
// the skips, and index the result by identity and by editor ID.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedRecordTable<Value: Sendable>: Sendable {
    public private(set) var values: [ResolvedFormID: Value] = [:]
    /// Decoded identities, lowest plugin priority first.
    public private(set) var orderedIDs: [ResolvedFormID] = []
    public private(set) var skipped = SkippedRecords()
    private var valuesByEditorID: [String: Value] = [:]

    public init() {}

    /// `resolve` gets the identity, the decoded record, and the plugin that won.
    public init<Decoded>(
        index: RecordIndex,
        types: Set<FourCC>,
        decode: (IndexedRecord) throws -> Decoded,
        editorID: (Decoded) -> String?,
        resolve: (ResolvedFormID, Decoded, String) -> Value
    ) {
        for id in index.orderedRecordIDs(of: types) {
            switch index.decodeIndexed(id, using: decode) {
            case let .decoded(decoded, sourcePlugin):
                let value = resolve(id, decoded, sourcePlugin)
                values[id] = value
                orderedIDs.append(id)
                if let editorID = editorID(decoded) {
                    valuesByEditorID[editorID.lowercased()] = value
                }
            case let .undecodable(canonical, error):
                let type: FourCC = index.records[canonical]?.record.type ?? "????"
                skipped.note(type, error: error)
            case .missing:
                continue
            }
        }
    }

    public var isEmpty: Bool {
        values.isEmpty
    }

    /// Values in load order, lowest plugin priority first.
    public var orderedValues: [Value] {
        orderedIDs.compactMap { values[$0] }
    }

    /// Exact identity first, then the same object ID under a differently cased plugin name.
    public func value(_ id: ResolvedFormID) -> Value? {
        values[id] ?? values.first { key, _ in
            key.objectID == id.objectID
                && key.plugin.caseInsensitiveCompare(id.plugin) == .orderedSame
        }?.value
    }

    public func value(editorID: String) -> Value? {
        valuesByEditorID[editorID.lowercased()]
    }
}
