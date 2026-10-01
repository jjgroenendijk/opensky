// The immutable value `WorldStateStore` hands off the main actor. Entries are in
// `ReferenceKey` order, so equal end states give equal snapshots whatever the
// mutation order. That makes it save input and a diffable readout.
// See docs/engine/runtime-state.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One dirty reference in a snapshot: its key and the deltas recorded for it.
nonisolated public struct WorldStateSnapshotEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let delta: ReferenceStateDelta

    public init(key: ReferenceKey, delta: ReferenceStateDelta) {
        self.key = key
        self.delta = delta
    }
}

/// One global whose runtime value differs from its plugin default. Others never
/// appear: `GlobalStore` re-derives them.
nonisolated public struct WorldStateGlobalSnapshotEntry: Equatable, Sendable {
    /// The GLOB record's session-stable key.
    public let key: ReferenceKey
    public let value: GlobalValue

    public init(key: ReferenceKey, value: GlobalValue) {
        self.key = key
        self.value = value
    }
}

/// Every runtime deviation in a store, independent of mutation order. Only dirty
/// references appear. Equality covers the entries and the allocator position, not
/// `sequence`, so it tests "same end state". The journal is separate.
nonisolated public struct WorldStateSnapshot: Equatable, Sendable {
    /// Dirty references in `ReferenceKey` total order.
    public let entries: [WorldStateSnapshotEntry]
    /// Overridden globals, in `ReferenceKey` order. Part of equality.
    public let globals: [WorldStateGlobalSnapshotEntry]
    /// The store's generated-key allocator position at snapshot time. Included
    /// because a restored session must resume allocating where this one left
    /// off, and because two stores that allocated different numbers of
    /// generated keys are not in the same end state.
    public let nextGeneratedSequence: UInt64
    /// The store's journal sequence at snapshot time, monotonic per session. A cell
    /// built from this snapshot keeps it, so the streamer can tell when it is stale.
    public let sequence: UInt64

    public static let empty = WorldStateSnapshot(entries: [], nextGeneratedSequence: 1, sequence: 0)

    public init(
        entries: [WorldStateSnapshotEntry],
        nextGeneratedSequence: UInt64,
        globals: [WorldStateGlobalSnapshotEntry] = [],
        sequence: UInt64 = 0
    ) {
        self.entries = entries
        self.nextGeneratedSequence = nextGeneratedSequence
        self.globals = globals
        self.sequence = sequence
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entries == rhs.entries
            && lhs.globals == rhs.globals
            && lhs.nextGeneratedSequence == rhs.nextGeneratedSequence
    }

    /// Number of dirty references.
    public var dirtyCount: Int {
        entries.count
    }

    /// Number of overridden globals.
    public var dirtyGlobalCount: Int {
        globals.count
    }

    public var isEmpty: Bool {
        entries.isEmpty && globals.isEmpty
    }

    /// Dirty keys, in the same total order as `entries`.
    public var keys: [ReferenceKey] {
        entries.map(\.key)
    }

    public subscript(key: ReferenceKey) -> ReferenceStateDelta? {
        entries.first { $0.key == key }?.delta
    }

    /// Runtime override recorded for a global, nil when it still matches the
    /// plugin. A linear scan, like `subscript(key:)`; a consumer resolving many
    /// globals builds a `GlobalResolution` from this snapshot instead.
    public func globalValue(for key: ReferenceKey) -> GlobalValue? {
        globals.first { $0.key == key }?.value
    }

    /// Every delta in one dictionary, for a consumer that looks up many keys.
    ///
    /// `subscript(key:)` is a linear scan, which is the right shape for the odd
    /// single probe and the wrong shape for a cell build, which asks once per
    /// reference. A build materializes this once and looks up from it instead.
    public func deltasByKey() -> [ReferenceKey: ReferenceStateDelta] {
        var result: [ReferenceKey: ReferenceStateDelta] = [:]
        result.reserveCapacity(entries.count)
        for entry in entries {
            result[entry.key] = entry.delta
        }
        return result
    }

    /// Dirty references last mutated under `cell`.
    public func entries(in cell: CellSceneLocation) -> [WorldStateSnapshotEntry] {
        entries.filter { $0.delta.cell == cell }
    }

    /// Dirty reference count for `cell`.
    public func dirtyCount(in cell: CellSceneLocation) -> Int {
        entries.count { $0.delta.cell == cell }
    }

    /// `entry`'s plugin baseline with this snapshot's delta applied. The
    /// baseline is re-derived from the record on every call, so a snapshot can
    /// never hand back a stale placement.
    public func resolvedState(for entry: RuntimeReferenceEntry) -> ReferenceState {
        ReferenceState(baseline: entry).applying(self[entry.key])
    }
}
