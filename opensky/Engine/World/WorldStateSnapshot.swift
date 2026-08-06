// Deterministic world-state snapshot (issue #159, roadmap item 10.1.2): the
// immutable value `WorldStateStore` hands to anything that is not the main
// thread.
//
// `WorldStateStore` is main-actor owned and holds dictionaries, whose iteration
// order is not deterministic. A snapshot flattens those dictionaries into an
// array ordered by `ReferenceKey`'s documented total order, so two stores that
// reached the same end state through different mutation orders produce equal
// snapshots. That property is what makes the snapshot usable as save input
// (10.1.4) and as a diffable UI readout (10.1.5).
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// One dirty reference in a snapshot: its key and the deltas recorded for it.
nonisolated struct WorldStateSnapshotEntry: Equatable, Sendable {
    let key: ReferenceKey
    let delta: ReferenceStateDelta
}

/// One global variable whose runtime value deviates from its plugin default
/// (issue #165). Globals with no override never appear, for the same reason
/// clean references do not: the default is re-derived from `GlobalStore`.
nonisolated struct WorldStateGlobalSnapshotEntry: Equatable, Sendable {
    /// The GLOB record's session-stable key.
    let key: ReferenceKey
    let value: GlobalValue
}

/// Immutable, order-independent view of every runtime deviation in a store.
///
/// Only dirty references appear: a reference with no delta is, by definition,
/// exactly what the plugin says it is, and the snapshot's consumer re-derives
/// that from the record index rather than from a copy here.
///
/// Equality is value equality over the ordered entries plus the allocator
/// position, so it is a genuine "same end state" test rather than a same-object
/// test. Mutation history is deliberately absent — the journal is a separate,
/// bounded, order-dependent product of the same store. `sequence` is excluded
/// from equality for the same reason: it says when the snapshot was taken, not
/// what state it describes, and two stores that reached the same end state
/// through different numbers of mutations are still equal.
nonisolated struct WorldStateSnapshot: Equatable, Sendable {
    /// Dirty references in `ReferenceKey` total order.
    let entries: [WorldStateSnapshotEntry]
    /// Overridden global variables, also in `ReferenceKey` total order
    /// (issue #165). Part of equality: two sessions whose globals differ are
    /// not in the same end state.
    let globals: [WorldStateGlobalSnapshotEntry]
    /// The store's generated-key allocator position at snapshot time. Included
    /// because a restored session must resume allocating where this one left
    /// off, and because two stores that allocated different numbers of
    /// generated keys are not in the same end state.
    let nextGeneratedSequence: UInt64
    /// The store's journal sequence at snapshot time, which is monotonic across
    /// the session (issue #160). A cell built from this snapshot records the
    /// value on its `CellScene`, so a later comparison against the store's
    /// current sequence tells the streamer whether the built scene is stale.
    let sequence: UInt64

    static let empty = WorldStateSnapshot(entries: [], nextGeneratedSequence: 1, sequence: 0)

    init(
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entries == rhs.entries
            && lhs.globals == rhs.globals
            && lhs.nextGeneratedSequence == rhs.nextGeneratedSequence
    }

    /// Number of dirty references.
    var dirtyCount: Int {
        entries.count
    }

    /// Number of overridden globals.
    var dirtyGlobalCount: Int {
        globals.count
    }

    var isEmpty: Bool {
        entries.isEmpty && globals.isEmpty
    }

    /// Dirty keys, in the same total order as `entries`.
    var keys: [ReferenceKey] {
        entries.map(\.key)
    }

    subscript(key: ReferenceKey) -> ReferenceStateDelta? {
        entries.first { $0.key == key }?.delta
    }

    /// Runtime override recorded for a global, nil when it still matches the
    /// plugin. A linear scan, like `subscript(key:)`; a consumer resolving many
    /// globals builds a `GlobalResolution` from this snapshot instead.
    func globalValue(for key: ReferenceKey) -> GlobalValue? {
        globals.first { $0.key == key }?.value
    }

    /// Every delta in one dictionary, for a consumer that looks up many keys.
    ///
    /// `subscript(key:)` is a linear scan, which is the right shape for the odd
    /// single probe and the wrong shape for a cell build, which asks once per
    /// reference. A build materializes this once and looks up from it instead.
    func deltasByKey() -> [ReferenceKey: ReferenceStateDelta] {
        var result: [ReferenceKey: ReferenceStateDelta] = [:]
        result.reserveCapacity(entries.count)
        for entry in entries {
            result[entry.key] = entry.delta
        }
        return result
    }

    /// Dirty references last mutated under `cell`.
    func entries(in cell: CellSceneLocation) -> [WorldStateSnapshotEntry] {
        entries.filter { $0.delta.cell == cell }
    }

    /// Dirty reference count for `cell`.
    func dirtyCount(in cell: CellSceneLocation) -> Int {
        entries.count { $0.delta.cell == cell }
    }

    /// `entry`'s plugin baseline with this snapshot's delta applied. The
    /// baseline is re-derived from the record on every call, so a snapshot can
    /// never hand back a stale placement.
    func resolvedState(for entry: RuntimeReferenceEntry) -> ReferenceState {
        ReferenceState(baseline: entry).applying(self[entry.key])
    }
}
