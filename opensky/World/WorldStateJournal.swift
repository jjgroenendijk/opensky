// World-state change journal (issue #159, roadmap item 10.1.2): the ordered log
// of every component mutation `WorldStateStore` applies.
//
// The journal is a first-class result, not a debug aid. Save serialization
// (10.1.4) replays it to know what changed since the last write, the sidebar
// readout (10.1.5) shows it, and Papyrus (M11) needs a causal order for the
// events it fires. That is why sequence numbers are monotonic across the whole
// store rather than per reference, and why they keep counting past the point
// where old entries are dropped.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// One recorded mutation.
///
/// `oldValue` is nil when the component had no delta before (the reference was
/// clean in that slot), and `newValue` is nil when the mutation was a reset. A
/// entry with both nil is never produced: the store skips no-op mutations.
nonisolated struct WorldStateJournalEntry: Equatable, Sendable {
    /// Store-wide monotonic sequence number, starting at 1. Never reused and
    /// never renumbered, so an entry stays comparable to one that has already
    /// been dropped from the bounded window.
    let sequence: UInt64
    let key: ReferenceKey
    let kind: WorldStateComponentKind
    /// Value before the mutation; nil when the slot was clean.
    let oldValue: WorldStateComponentValue?
    /// Value after the mutation; nil when the mutation cleared the slot.
    let newValue: WorldStateComponentValue?
    /// Cell the mutation was recorded under, when the caller supplied one.
    let cell: CellSceneLocation?

    /// True when this entry restored a slot to its plugin default.
    var isReset: Bool {
        newValue == nil
    }
}

/// Bounded, ordered window over the most recent `WorldStateJournalEntry`
/// values.
///
/// The cap exists because the journal is unbounded work otherwise: a running
/// game mutates state forever, and a log that grows forever is a leak with a
/// slow fuse. Once the window is full the oldest entry is dropped to make room,
/// `droppedCount` counts how many were lost, and sequence numbers keep
/// increasing so a consumer can tell the difference between "nothing happened"
/// and "I missed it".
///
/// The default cap is `WorldStateJournal.defaultCapacity` (4096 entries).
/// Storage is a fixed-size ring, so recording is O(1) and the memory cost is
/// bounded at construction rather than growing to a high-water mark.
nonisolated struct WorldStateJournal: Sendable {
    /// Entries retained before the oldest starts falling off the back. Sized so
    /// that a normal play session's recent history — a few thousand
    /// activations, moves and enable toggles — fits, while the memory cost
    /// stays a fixed few hundred kilobytes.
    static let defaultCapacity = 4096

    /// Maximum number of retained entries. Always at least 1.
    let capacity: Int
    /// Entries dropped because the window was full.
    private(set) var droppedCount = 0
    /// Sequence number the next recorded entry will carry.
    private(set) var nextSequence: UInt64 = 1

    private var storage: [WorldStateJournalEntry?]
    private var start = 0
    private var retained = 0

    /// Capacities below 1 are clamped rather than rejected: a journal is
    /// runtime bookkeeping and must never be the thing that fails a mutation.
    init(capacity: Int = WorldStateJournal.defaultCapacity) {
        self.capacity = max(1, capacity)
        storage = Array(repeating: nil, count: self.capacity)
    }

    /// Retained entries, oldest first.
    var entries: [WorldStateJournalEntry] {
        (0 ..< retained).compactMap { storage[(start + $0) % capacity] }
    }

    /// Number of retained entries, which is `min(total recorded, capacity)`.
    var entryCount: Int {
        retained
    }

    var isEmpty: Bool {
        retained == 0
    }

    /// Oldest retained entry, nil when nothing has been recorded or everything
    /// recorded has already been dropped.
    var oldest: WorldStateJournalEntry? {
        retained == 0 ? nil : storage[start]
    }

    /// Most recently recorded entry.
    var newest: WorldStateJournalEntry? {
        retained == 0 ? nil : storage[(start + retained - 1) % capacity]
    }

    /// Appends a mutation, dropping the oldest entry when the window is full,
    /// and returns the entry as recorded (sequence number included).
    @discardableResult
    mutating func record(
        key: ReferenceKey,
        kind: WorldStateComponentKind,
        oldValue: WorldStateComponentValue?,
        newValue: WorldStateComponentValue?,
        cell: CellSceneLocation?
    ) -> WorldStateJournalEntry {
        let entry = WorldStateJournalEntry(
            sequence: nextSequence,
            key: key,
            kind: kind,
            oldValue: oldValue,
            newValue: newValue,
            cell: cell
        )
        nextSequence &+= 1
        if retained == capacity {
            storage[start] = entry
            start = (start + 1) % capacity
            droppedCount += 1
        } else {
            storage[(start + retained) % capacity] = entry
            retained += 1
        }
        return entry
    }

    /// Drops every retained entry. Sequence numbering and `droppedCount` are
    /// deliberately untouched: clearing the window is not the same as claiming
    /// the mutations never happened.
    mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        start = 0
        retained = 0
    }
}
