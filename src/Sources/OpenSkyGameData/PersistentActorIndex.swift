// Placed references in persistent cell children. Only the persistent groups are
// read, because a quest alias can only hold a persistent reference, and the
// temporary groups are most of the file. The game keeps these references in every
// cell, loaded or not, so an alias search outside the loaded area reads them
// (docs/engine/quest-state.md).

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM

/// One persistent placement of the load order.
nonisolated public struct PersistentPlacement: Sendable {
    nonisolated public enum Record: Sendable {
        case reference(PlacedReference)
        case actor(PlacedActor)
    }

    public let key: ReferenceKey
    /// The FormID as the plugin spelled it.
    public let formID: FormID
    public let record: Record
    /// The resolved NPC base of a placed actor.
    public let actorBase: ReferenceKey?

    var startsDisabled: Bool {
        switch record {
        case let .reference(reference): reference.isInitiallyDisabled
        case let .actor(actor): actor.isInitiallyDisabled
        }
    }
}

nonisolated public enum PersistentActorIndex {
    /// Every persistent REFR and ACHR of the load order, in key order. A later
    /// plugin's copy of a reference replaces an earlier one.
    public static func placements(
        plugins: [(name: String, file: ESMFile)],
        index: RecordIndex
    ) -> [PersistentPlacement] {
        var byKey: [ReferenceKey: PersistentPlacement] = [:]
        for plugin in plugins {
            for type: FourCC in ["CELL", "WRLD"] {
                guard let top = plugin.file.topGroup(of: type) else { continue }
                visit(top, depth: 0) { record in
                    guard
                        let placement = placement(record, plugin: plugin.name, index: index)
                    else { return }
                    byKey[placement.key] = placement
                }
            }
        }
        return byKey.keys.sorted().compactMap { byKey[$0] }
    }

    /// Each base with one persistent placed actor, mapped to that actor. A base placed
    /// more than once takes its one actor that starts enabled; with several or none of
    /// those it has no single answer and is left out.
    public static func singleReferences(
        in placements: [PersistentPlacement]
    ) -> [ReferenceKey: ReferenceKey] {
        var placed: [ReferenceKey: [PersistentPlacement]] = [:]
        for placement in placements {
            guard let base = placement.actorBase else { continue }
            placed[base, default: []].append(placement)
        }
        return placed.compactMapValues { copies in
            if copies.count == 1 {
                return copies[0].key
            }
            let enabled = copies.filter { !$0.startsDisabled }
            return enabled.count == 1 ? enabled[0].key : nil
        }
    }

    private static func placement(
        _ record: ESMRecord, plugin: String, index: RecordIndex
    ) -> PersistentPlacement? {
        switch record.type {
        case "ACHR":
            guard
                let actor = attempt({ try PlacedActor(record: record) }),
                let key = index.resolvedID(actor.formID, fromPlugin: plugin),
                let base = index.resolvedID(actor.base, fromPlugin: plugin)
            else { return nil }
            return PersistentPlacement(
                key: ReferenceKey(resolved: key), formID: actor.formID,
                record: .actor(actor), actorBase: ReferenceKey(resolved: base)
            )
        case "REFR":
            guard
                let reference = attempt({ try PlacedReference(record: record) }),
                let key = index.resolvedID(reference.formID, fromPlugin: plugin)
            else { return nil }
            return PersistentPlacement(
                key: ReferenceKey(resolved: key), formID: reference.formID,
                record: .reference(reference), actorBase: nil
            )
        default:
            return nil
        }
    }

    /// Cell groups nest at most a few levels; the bound stops a malformed file.
    private static let maximumDepth = 8

    private static func visit(_ group: ESMGroup, depth: Int, _ body: (ESMRecord) -> Void) {
        guard depth < maximumDepth, let children = attempt({ try group.children() }) else { return }
        for child in children {
            switch child {
            case let .record(record):
                if group.kind == .cellPersistentChildren, !record.isDeleted {
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
