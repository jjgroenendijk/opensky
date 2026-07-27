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

/// Immutable, order-independent view of every runtime deviation in a store.
///
/// Only dirty references appear: a reference with no delta is, by definition,
/// exactly what the plugin says it is, and the snapshot's consumer re-derives
/// that from the record index rather than from a copy here.
///
/// Equality is value equality over the ordered entries plus the allocator
/// position, so it is a genuine "same end state" test rather than a same-object
/// test. Mutation history is deliberately absent — the journal is a separate,
/// bounded, order-dependent product of the same store.
nonisolated struct WorldStateSnapshot: Equatable, Sendable {
    /// Dirty references in `ReferenceKey` total order.
    let entries: [WorldStateSnapshotEntry]
    /// The store's generated-key allocator position at snapshot time. Included
    /// because a restored session must resume allocating where this one left
    /// off, and because two stores that allocated different numbers of
    /// generated keys are not in the same end state.
    let nextGeneratedSequence: UInt64

    static let empty = WorldStateSnapshot(entries: [], nextGeneratedSequence: 1)

    /// Number of dirty references.
    var dirtyCount: Int {
        entries.count
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    /// Dirty keys, in the same total order as `entries`.
    var keys: [ReferenceKey] {
        entries.map(\.key)
    }

    subscript(key: ReferenceKey) -> ReferenceStateDelta? {
        entries.first { $0.key == key }?.delta
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
