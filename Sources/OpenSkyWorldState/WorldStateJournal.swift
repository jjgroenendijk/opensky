// The ordered log of every mutation `WorldStateStore` applies. Save and the
// sidebar read it, and Papyrus needs its causal order, so sequence numbers
// are store-wide and keep counting after old entries drop. Global writes have
// their own entry type and window but share the counter, so merging both logs
// by `sequence` gives the true order. See docs/engine/runtime-state.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One recorded component mutation.
///
/// `oldValue` is nil when the component had no delta before (the reference was
/// clean in that slot), and `newValue` is nil when the mutation was a reset. A
/// entry with both nil is never produced: the store skips no-op mutations.
nonisolated public struct WorldStateJournalEntry: Equatable, Sendable {
    /// Store-wide monotonic sequence number, starting at 1. Never reused and
    /// never renumbered, so an entry stays comparable to one that has already
    /// been dropped from the bounded window.
    public let sequence: UInt64
    public let key: ReferenceKey
    public let kind: WorldStateComponentKind
    /// Value before the mutation; nil when the slot was clean.
    public let oldValue: WorldStateComponentValue?
    /// Value after the mutation; nil when the mutation cleared the slot.
    public let newValue: WorldStateComponentValue?
    /// Cell the mutation was recorded under, when the caller supplied one.
    public let cell: CellSceneLocation?

    /// True when this entry restored a slot to its plugin default.
    public var isReset: Bool {
        newValue == nil
    }
}

/// One recorded global-variable mutation.
///
/// `key` is the GLOB record's session-stable `ReferenceKey`, not a placed
/// object's, and there is no cell: a global belongs to the session rather than
/// to any location, which is also why a global write does not trigger a cell
/// rebuild.
nonisolated public struct WorldStateGlobalJournalEntry: Equatable, Sendable {
    /// Drawn from the same counter as `WorldStateJournalEntry.sequence`, so the
    /// two logs interleave into one causal order.
    public let sequence: UInt64
    public let key: ReferenceKey
    /// Value before the mutation; nil when the global still had its plugin
    /// default.
    public let oldValue: GlobalValue?
    /// Value after the mutation; nil when the mutation reset the global to its
    /// plugin default.
    public let newValue: GlobalValue?

    /// True when this entry restored the global to its plugin default.
    public var isReset: Bool {
        newValue == nil
    }
}

/// Bounded ring windows over the most recent reference and global entries.
/// When a window is full the oldest entry drops and `droppedCount` rises, so a
/// consumer can tell "nothing happened" from "I missed it". Each window holds
/// `WorldStateJournal.defaultCapacity` entries, so one kind cannot evict the other.
nonisolated public struct WorldStateJournal: Sendable {
    /// Entries retained before the oldest starts falling off the back. Sized so
    /// that a normal play session's recent history — a few thousand
    /// activations, moves and enable toggles — fits, while the memory cost
    /// stays a fixed few hundred kilobytes.
    public static let defaultCapacity = 4096

    /// Maximum number of retained entries, per window. Always at least 1.
    public let capacity: Int
    /// Sequence number the next recorded entry will carry, whichever window it
    /// lands in.
    public private(set) var nextSequence: UInt64 = 1

    private var components: JournalRing<WorldStateJournalEntry>
    private var globals: JournalRing<WorldStateGlobalJournalEntry>

    /// Capacities below 1 are clamped rather than rejected: a journal is
    /// runtime bookkeeping and must never be the thing that fails a mutation.
    public init(capacity: Int = WorldStateJournal.defaultCapacity) {
        let bounded = max(1, capacity)
        self.capacity = bounded
        components = JournalRing(capacity: bounded)
        globals = JournalRing(capacity: bounded)
    }

    // MARK: - Component entries

    /// Retained component entries, oldest first.
    public var entries: [WorldStateJournalEntry] {
        components.entries
    }

    /// Component entries dropped because the window was full.
    public var droppedCount: Int {
        components.droppedCount
    }

    /// Appends a component mutation, dropping the oldest entry when the window
    /// is full, and returns the entry as recorded (sequence number included).
    @discardableResult
    public mutating func record(
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
    public var globalEntries: [WorldStateGlobalJournalEntry] {
        globals.entries
    }

    /// Global entries dropped because the window was full.
    public var droppedGlobalCount: Int {
        globals.droppedCount
    }

    /// Appends a global mutation, taking the next shared sequence number.
    @discardableResult
    public mutating func recordGlobal(
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
    public mutating func removeAll() {
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

    var entries: [Entry] {
        (0 ..< retained).compactMap { storage[(start + $0) % capacity] }
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
