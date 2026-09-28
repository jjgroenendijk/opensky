// Runtime reference index (issue #158 stage B): the decoded REFR/ACHR records
// of one built cell, retained beside its render data and addressable by
// session-stable `ReferenceKey`.
//
// Lifetime is the cell's. The index is assembled once on the build queue and
// is immutable afterwards, so it crosses to the main thread as part of the
// `CellScene` value without locking. Mutable runtime state that must outlive a
// cell unload belongs in a store above this layer, not here.

import Foundation
import OpenSkyFormatsESM

/// The decoded record a runtime reference stands for. REFR and ACHR are the
/// two placement records a cell build retains; both are plain value types.
nonisolated public enum RuntimeReferenceRecord: Sendable {
    case reference(PlacedReference)
    case actor(PlacedActor)
}

/// One indexed placement: its stable key, the raw FormID it was placed under,
/// whether the cell stored it persistently, and the decoded record.
nonisolated public struct RuntimeReferenceEntry: Sendable {
    /// Session-stable identity, resolved through the plugin's master list.
    public let key: ReferenceKey
    /// Load-order-relative FormID exactly as the plugin spelled it. Retained
    /// because collision raycasts and interaction metadata address references
    /// by raw FormID, so both lookup directions must work.
    public let formID: FormID
    /// True when the record came from a cell persistent children group or from
    /// the worldspace persistent CELL. Persistent references outlive the
    /// streaming lifetime of the cell they are rendered in.
    public let isPersistent: Bool
    public let record: RuntimeReferenceRecord

    public var placedReference: PlacedReference? {
        guard case let .reference(reference) = record else { return nil }
        return reference
    }

    public var placedActor: PlacedActor? {
        guard case let .actor(actor) = record else { return nil }
        return actor
    }
}

/// Immutable per-cell lookup over `RuntimeReferenceEntry`, keyed both by
/// `ReferenceKey` and by raw FormID.
///
/// Duplicate keys resolve last-writer-wins, matching the FormID dedupe the
/// exterior reference merge already performs: a worldspace-persistent record
/// overriding a local placement of the same object must leave exactly one
/// entry behind.
nonisolated public struct RuntimeReferenceIndex: Sendable {
    private var entriesByKey: [ReferenceKey: RuntimeReferenceEntry]
    private var keysByFormID: [FormID: ReferenceKey]

    /// Cells built without reference retention (synthetic render tests) use
    /// this rather than an optional field.
    public static let empty = RuntimeReferenceIndex(entries: [])

    public init(entries: [RuntimeReferenceEntry]) {
        var byKey: [ReferenceKey: RuntimeReferenceEntry] = [:]
        var byFormID: [FormID: ReferenceKey] = [:]
        byKey.reserveCapacity(entries.count)
        byFormID.reserveCapacity(entries.count)
        for entry in entries {
            byKey[entry.key] = entry
            byFormID[entry.formID] = entry.key
        }
        entriesByKey = byKey
        keysByFormID = byFormID
    }

    public var count: Int {
        entriesByKey.count
    }

    public var isEmpty: Bool {
        entriesByKey.isEmpty
    }

    public subscript(key: ReferenceKey) -> RuntimeReferenceEntry? {
        entriesByKey[key]
    }

    public func entry(for formID: FormID) -> RuntimeReferenceEntry? {
        guard let key = keysByFormID[formID] else { return nil }
        return entriesByKey[key]
    }

    /// Keys in `ReferenceKey`'s total order. Dictionary iteration order is
    /// nondeterministic, so every caller that walks the whole index — save
    /// serialization and inspection UI among them — walks it through here.
    public func sortedKeys() -> [ReferenceKey] {
        entriesByKey.keys.sorted()
    }

    /// Entries in `sortedKeys()` order.
    public func sortedEntries() -> [RuntimeReferenceEntry] {
        sortedKeys().compactMap { entriesByKey[$0] }
    }
}
