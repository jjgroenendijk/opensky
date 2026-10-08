// Placed actors in persistent cell children, keyed by their NPC base. Only the
// persistent groups are read, because a quest alias can only hold a persistent
// reference, and the temporary groups are most of the file.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public enum PersistentActorIndex {
    /// Each base that has exactly one persistent placed actor in the load order,
    /// mapped to that actor. A base placed twice has no single answer, so it is left out.
    public static func singleReferences(
        plugins: [(name: String, file: ESMFile)],
        index: RecordIndex
    ) -> [ReferenceKey: ReferenceKey] {
        var placed: [ReferenceKey: Set<ReferenceKey>] = [:]
        for plugin in plugins {
            for type: FourCC in ["CELL", "WRLD"] {
                guard let top = plugin.file.topGroup(of: type) else { continue }
                visit(top, depth: 0) { record in
                    guard
                        let actor = try? PlacedActor(record: record),
                        let base = index.resolvedID(actor.base, fromPlugin: plugin.name),
                        let reference = index.resolvedID(actor.formID, fromPlugin: plugin.name)
                    else { return }
                    placed[ReferenceKey(resolved: base), default: []]
                        .insert(ReferenceKey(resolved: reference))
                }
            }
        }
        return placed.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    /// Cell groups nest at most a few levels; the bound stops a malformed file.
    private static let maximumDepth = 8

    private static func visit(_ group: ESMGroup, depth: Int, _ body: (ESMRecord) -> Void) {
        guard depth < maximumDepth, let children = try? group.children() else { return }
        for child in children {
            switch child {
            case let .record(record):
                if group.kind == .cellPersistentChildren, record.type == "ACHR", !record.isDeleted {
                    body(record)
                }
            case let .group(inner):
                if inner.kind != .cellTemporaryChildren {
                    visit(inner, depth: depth + 1, body)
                }
            }
        }
    }
}
