// The decoded REFR/ACHR records of one built cell, keyed by `ReferenceKey`.
// Built once on the build queue and immutable, so it crosses to the main thread in
// `CellScene` without a lock. State that outlives the cell lives in a store above.

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
    /// `VMAD` scripts of the base object, which the reference runs too.
    public let baseScripts: [AttachedScript]

    /// The scripts this reference runs: its own over its base object's.
    public var scripts: [AttachedScript] {
        let own = placedReference?.scriptData.scripts ?? placedActor?.scriptData.scripts ?? []
        return own.overlaying(base: baseScripts)
    }

    public var placedReference: PlacedReference? {
        guard case let .reference(reference) = record else { return nil }
        return reference
    }

    public var placedActor: PlacedActor? {
        guard case let .actor(actor) = record else { return nil }
        return actor
    }

    public init(
        key: ReferenceKey,
        formID: FormID,
        isPersistent: Bool,
        record: RuntimeReferenceRecord,
        baseScripts: [AttachedScript] = []
    ) {
        self.key = key
        self.formID = formID
        self.isPersistent = isPersistent
        self.record = record
        self.baseScripts = baseScripts
    }
}

/// Immutable per-cell lookup by `ReferenceKey` and by FormID. The last duplicate wins,
/// as in the exterior reference merge.
nonisolated public struct RuntimeReferenceIndex: Sendable {
    private var entriesByKey: [ReferenceKey: RuntimeReferenceEntry]
    private var keysByFormID: [FormID: ReferenceKey]
    /// ACHR entries in `sortedKeys()` order, built once: per-frame actor systems read
    /// this list, and the index never changes after a build.
    public let sortedActorEntries: [RuntimeReferenceEntry]

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
        sortedActorEntries = byKey.values
            .filter { $0.placedActor != nil }
            .sorted { $0.key < $1.key }
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
