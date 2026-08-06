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
// Issue #165 added a second kind of entry for global-variable writes. Rather
// than widen `WorldStateJournalEntry` — whose `kind` is a component slot on a
// reference, which a global does not have — globals get their own entry type
// and their own retained window, sharing the one sequence counter. Interleaving
// the two logs by `sequence` therefore reproduces the exact order the mutations
// happened in, which is the property Papyrus and the save layer actually need.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// One recorded component mutation.
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

/// One recorded global-variable mutation (issue #165).
///
/// `key` is the GLOB record's session-stable `ReferenceKey`, not a placed
/// object's, and there is no cell: a global belongs to the session rather than
/// to any location, which is also why a global write does not trigger a cell
/// rebuild.
nonisolated struct WorldStateGlobalJournalEntry: Equatable, Sendable {
    /// Drawn from the same counter as `WorldStateJournalEntry.sequence`, so the
    /// two logs interleave into one causal order.
    let sequence: UInt64
    let key: ReferenceKey
    /// Value before the mutation; nil when the global still had its plugin
    /// default.
    let oldValue: GlobalValue?
    /// Value after the mutation; nil when the mutation reset the global to its
    /// plugin default.
    let newValue: GlobalValue?

    /// True when this entry restored the global to its plugin default.
    var isReset: Bool {
        newValue == nil
    }
}

/// Bounded, ordered window over the most recent `WorldStateJournalEntry` and
/// `WorldStateGlobalJournalEntry` values.
///
/// The cap exists because the journal is unbounded work otherwise: a running
/// game mutates state forever, and a log that grows forever is a leak with a
/// slow fuse. Once a window is full the oldest entry is dropped to make room,
/// `droppedCount` counts how many were lost, and sequence numbers keep
/// increasing so a consumer can tell the difference between "nothing happened"
/// and "I missed it".
///
/// The default cap is `WorldStateJournal.defaultCapacity` (4096 entries), and
/// each window carries it separately: a burst of global writes must not evict
/// the reference history, and the reverse. Storage is a fixed-size ring, so
/// recording is O(1) and the memory cost is bounded at construction rather than
/// growing to a high-water mark.
nonisolated struct WorldStateJournal: Sendable {
    /// Entries retained before the oldest starts falling off the back. Sized so
    /// that a normal play session's recent history — a few thousand
    /// activations, moves and enable toggles — fits, while the memory cost
    /// stays a fixed few hundred kilobytes.
    static let defaultCapacity = 4096

    /// Maximum number of retained entries, per window. Always at least 1.
    let capacity: Int
    /// Sequence number the next recorded entry will carry, whichever window it
    /// lands in.
    private(set) var nextSequence: UInt64 = 1

    private var components: JournalRing<WorldStateJournalEntry>
    private var globals: JournalRing<WorldStateGlobalJournalEntry>

    /// Capacities below 1 are clamped rather than rejected: a journal is
    /// runtime bookkeeping and must never be the thing that fails a mutation.
    init(capacity: Int = WorldStateJournal.defaultCapacity) {
        let bounded = max(1, capacity)
        self.capacity = bounded
        components = JournalRing(capacity: bounded)
        globals = JournalRing(capacity: bounded)
    }

    // MARK: - Component entries

    /// Retained component entries, oldest first.
    var entries: [WorldStateJournalEntry] {
        components.entries
    }

    /// Component entries dropped because the window was full.
    var droppedCount: Int {
        components.droppedCount
    }

    /// Number of retained component entries, which is
    /// `min(total recorded, capacity)`.
    var entryCount: Int {
        components.count
    }

    var isEmpty: Bool {
        components.isEmpty
    }

    /// Oldest retained component entry, nil when nothing has been recorded or
    /// everything recorded has already been dropped.
    var oldest: WorldStateJournalEntry? {
        components.oldest
    }

    /// Most recently recorded component entry.
    var newest: WorldStateJournalEntry? {
        components.newest
    }

    /// Appends a component mutation, dropping the oldest entry when the window
    /// is full, and returns the entry as recorded (sequence number included).
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
        components.append(entry)
        return entry
    }

    // MARK: - Global entries

    /// Retained global entries, oldest first.
    var globalEntries: [WorldStateGlobalJournalEntry] {
        globals.entries
    }

    /// Global entries dropped because the window was full.
    var droppedGlobalCount: Int {
        globals.droppedCount
    }

    var globalEntryCount: Int {
        globals.count
    }

    var newestGlobal: WorldStateGlobalJournalEntry? {
        globals.newest
    }

    /// Appends a global mutation, taking the next shared sequence number.
    @discardableResult
    mutating func recordGlobal(
        key: ReferenceKey,
        oldValue: GlobalValue?,
        newValue: GlobalValue?
    ) -> WorldStateGlobalJournalEntry {
        let entry = WorldStateGlobalJournalEntry(
            sequence: nextSequence,
            key: key,
            oldValue: oldValue,
            newValue: newValue
        )
        nextSequence &+= 1
        globals.append(entry)
        return entry
    }

    // MARK: - Clearing

    /// Drops every retained entry from both windows. Sequence numbering and the
    /// dropped counts are deliberately untouched: clearing a window is not the
    /// same as claiming the mutations never happened.
    mutating func removeAll() {
        components.removeAll()
        globals.removeAll()
    }
}

/// Fixed-size ring of journal entries. Private to the journal: it exists only
/// so the component window and the global window share one implementation
/// rather than one copy each.
nonisolated private struct JournalRing<Entry: Sendable>: Sendable {
    let capacity: Int
    private(set) var droppedCount = 0
    private var storage: [Entry?]
    private var start = 0
    private var retained = 0

    init(capacity: Int) {
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    var count: Int {
        retained
    }

    var isEmpty: Bool {
        retained == 0
    }

    var entries: [Entry] {
        (0 ..< retained).compactMap { storage[(start + $0) % capacity] }
    }

    var oldest: Entry? {
        retained == 0 ? nil : storage[start]
    }

    var newest: Entry? {
        retained == 0 ? nil : storage[(start + retained - 1) % capacity]
    }

    mutating func append(_ entry: Entry) {
        if retained == capacity {
            storage[start] = entry
            start = (start + 1) % capacity
            droppedCount += 1
        } else {
            storage[(start + retained) % capacity] = entry
            retained += 1
        }
    }

    mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        start = 0
        retained = 0
    }
}
