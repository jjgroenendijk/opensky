// Mutable world state: the one place runtime deviations from plugin data live,
// mutated by Papyrus, inventory and quests. See docs/engine/runtime-state.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// Main-actor store of per-reference runtime state; only `snapshot()` values cross
/// threads. Nothing throws: state may be recorded for a key that is not resident.
/// Baselines are never stored; `resolvedState(for:)` re-derives them from the record.
@MainActor
public final class WorldStateStore {
    /// Per-reference deltas. Only dirty references have an entry: clearing the
    /// last component removes the key entirely, which is what keeps
    /// `dirtyCount` honest.
    private var deltas: [ReferenceKey: ReferenceStateDelta] = [:]
    /// Runtime global overrides, keyed by the GLOB's key. Separate from components,
    /// because a global has no cell and must not trigger a cell rebuild.
    private var globalValues: [ReferenceKey: GlobalValue] = [:]
    /// Dirty reference count per cell, maintained incrementally so a sidebar
    /// readout costs a dictionary lookup rather than a scan.
    private var dirtyCountsByCell: [CellSceneLocation: Int] = [:]
    private var changeJournal: WorldStateJournal
    private var allocator: GeneratedReferenceAllocator

    /// Fires per journalled mutation with its cell (or nil) and the next snapshot's
    /// sequence. `CellStreamer` uses it to rebuild stale cells; it needs no payload.
    public var onMutation: ((CellSceneLocation?, UInt64) -> Void)?

    /// Fires per journalled global mutation with the next snapshot's sequence.
    /// Separate from `onMutation`, so a clock ticking a global each frame does not
    /// rebuild every cell. Global readers refresh `GlobalResolution` here.
    public var onGlobalMutation: ((UInt64) -> Void)?

    /// Redirect for writes to `GameHour`, `GameDaysPassed`, `GameDay`, `GameMonth` and
    /// `GameYear`: the clock moves instead of storing an override. Returns the prior
    /// value, or nil to decline. Does not fire `onGlobalMutation`, so weather is stable.
    public var onTimeGlobalWrite: ((GameClock.TimeGlobal, Float) -> Float?)?

    /// - Parameters:
    ///   - journalCapacity: retained change-journal entries; see
    ///     `WorldStateJournal.defaultCapacity`.
    ///   - allocator: generated-key allocator to adopt, for a restored session
    ///     that must resume its sequence.
    public init(
        journalCapacity: Int = WorldStateJournal.defaultCapacity,
        allocator: GeneratedReferenceAllocator = GeneratedReferenceAllocator()
    ) {
        changeJournal = WorldStateJournal(capacity: journalCapacity)
        self.allocator = allocator
    }

    // MARK: - Reading components

    /// The runtime override in `type`'s slot for `key`, or nil when that slot
    /// still matches the plugin.
    public func component<Component: WorldStateComponent>(
        _ type: Component.Type,
        for key: ReferenceKey
    ) -> Component? {
        deltas[key]?.component(type)
    }

    /// Every delta recorded for `key`, or nil when the reference is clean.
    public func delta(for key: ReferenceKey) -> ReferenceStateDelta? {
        deltas[key]
    }

    /// `entry`'s plugin baseline with this store's deltas applied.
    public func resolvedState(for entry: RuntimeReferenceEntry) -> ReferenceState {
        ReferenceState(baseline: entry).applying(deltas[entry.key])
    }

    // MARK: - Writing components

    /// Records `component` for `key` in `cell`. An equal value is a no-op. A value
    /// equal to the plugin default still marks the reference dirty; use `reset(_:for:)`.
    /// - Returns: true when the stored state changed.
    @discardableResult
    public func set(
        _ component: some WorldStateComponent,
        for key: ReferenceKey,
        in cell: CellSceneLocation? = nil
    ) -> Bool {
        let value = component.erased
        var delta = deltas[key] ?? ReferenceStateDelta()
        guard delta[value.kind] != value else { return false }
        let wasClean = delta.isEmpty
        let previous = delta.set(value)
        let previousCell = delta.cell
        delta.record(cell: cell)
        deltas[key] = delta
        if wasClean {
            adjustCellCount(delta.cell, by: 1)
        } else if previousCell != delta.cell {
            adjustCellCount(previousCell, by: -1)
            adjustCellCount(delta.cell, by: 1)
        }
        changeJournal.record(
            key: key,
            kind: value.kind,
            oldValue: previous,
            newValue: value,
            cell: delta.cell
        )
        onMutation?(delta.cell, changeJournal.nextSequence)
        return true
    }

    /// Drops one component's delta, restoring that slot to the plugin default.
    ///
    /// - Returns: true when a delta was actually removed.
    @discardableResult
    public func reset(_ kind: WorldStateComponentKind, for key: ReferenceKey) -> Bool {
        guard var delta = deltas[key], let previous = delta.clear(kind) else { return false }
        let cell = delta.cell
        if delta.isEmpty {
            deltas.removeValue(forKey: key)
            adjustCellCount(cell, by: -1)
        } else {
            deltas[key] = delta
        }
        changeJournal.record(
            key: key,
            kind: kind,
            oldValue: previous,
            newValue: nil,
            cell: cell
        )
        onMutation?(cell, changeJournal.nextSequence)
        return true
    }

    /// Drops every delta for `key`, restoring the whole reference to its plugin
    /// default. One journal entry is written per cleared component, in
    /// `WorldStateComponentKind.order` so the log stays deterministic.
    ///
    /// - Returns: true when the reference was dirty.
    @discardableResult
    public func reset(_ key: ReferenceKey) -> Bool {
        guard let delta = deltas[key] else { return false }
        for kind in delta.sortedKinds {
            reset(kind, for: key)
        }
        return true
    }

    /// Drops every delta in the store. Journal sequence numbering continues,
    /// because these resets did happen.
    public func resetAll() {
        for key in sortedDirtyKeys() {
            reset(key)
        }
    }

    // MARK: - Global variables

    /// Runtime override for a global, or nil when it still holds its plugin
    /// default. Callers wanting the effective value — default included — go
    /// through `globalResolution(defaults:)` instead.
    public func globalValue(for key: ReferenceKey) -> GlobalValue? {
        globalValues[key]
    }

    /// Writes `value` to a global, coerced to its type: a short rounds 3.7 to 4. An
    /// equal value is a no-op; the plugin default still counts as an override.
    /// - Returns: true when the stored value changed.
    @discardableResult
    public func setGlobal(_ value: GlobalValue, for key: ReferenceKey) -> Bool {
        guard globalValues[key] != value else { return false }
        let previous = globalValues[key]
        globalValues[key] = value
        changeJournal.recordGlobal(key: key, oldValue: previous, newValue: value)
        onGlobalMutation?(changeJournal.nextSequence)
        return true
    }

    /// Writes a raw number to a global of declared type `type`.
    @discardableResult
    public func setGlobal(_ raw: Float, type: Global.ValueType, for key: ReferenceKey) -> Bool {
        setGlobal(GlobalValue(type: type, rawValue: raw), for: key)
    }

    /// Writes a raw number to the global `id` names, typed by `defaults`. A time
    /// global moves the clock through `onTimeGlobalWrite` instead.
    /// - Returns: false for an unknown global or a no-op write.
    @discardableResult
    public func setGlobal(_ raw: Float, formID id: FormID, defaults: GlobalStore) -> Bool {
        guard let global = defaults.global(id), let key = defaults.key(for: id) else {
            return false
        }
        if
            let editorID = global.editorID,
            let timeGlobal = GameClock.TimeGlobal(editorID: editorID),
            let previous = onTimeGlobalWrite?(timeGlobal, raw)
        {
            let oldValue = GlobalValue(type: global.valueType, rawValue: previous)
            let newValue = GlobalValue(type: global.valueType, rawValue: raw)
            guard oldValue != newValue else { return false }
            changeJournal.recordGlobal(key: key, oldValue: oldValue, newValue: newValue)
            return true
        }
        return setGlobal(raw, type: global.valueType, for: key)
    }

    /// Drops a global's override, restoring its plugin default.
    ///
    /// - Returns: true when an override was actually removed.
    @discardableResult
    public func resetGlobal(for key: ReferenceKey) -> Bool {
        guard let previous = globalValues.removeValue(forKey: key) else { return false }
        changeJournal.recordGlobal(key: key, oldValue: previous, newValue: nil)
        onGlobalMutation?(changeJournal.nextSequence)
        return true
    }

    /// Drops every global override, in `ReferenceKey` total order so the
    /// journal stays deterministic.
    public func resetAllGlobals() {
        for key in sortedOverriddenGlobalKeys() {
            resetGlobal(for: key)
        }
    }

    /// Number of globals deviating from plugin data.
    public var overriddenGlobalCount: Int {
        globalValues.count
    }

    /// Overridden global keys in `ReferenceKey` total order.
    public func sortedOverriddenGlobalKeys() -> [ReferenceKey] {
        globalValues.keys.sorted()
    }

    /// Retained global journal entries, oldest first.
    public var globalJournalEntries: [WorldStateGlobalJournalEntry] {
        changeJournal.globalEntries
    }

    /// Global journal entries dropped because the window was full.
    public var droppedGlobalJournalEntryCount: Int {
        changeJournal.droppedGlobalCount
    }

    /// The global lookup seam: session overrides over `defaults`. With `clock`, the
    /// five time globals are projected from it at this moment.
    public func globalResolution(
        defaults: GlobalStore?, clock: GameClock? = nil
    ) -> GlobalResolution {
        GlobalResolution(defaults: defaults, overrides: globalValues, clock: clock)
    }

    // MARK: - Restoring a saved session

    /// Replaces every delta with `snapshot`'s and resumes the key allocator, which is
    /// how a save becomes live. Nothing is journalled and the window is cleared, so
    /// `snapshot()` equals the input. One unattributed `onMutation` rebuilds all cells.
    public func restore(from snapshot: WorldStateSnapshot) {
        deltas = [:]
        dirtyCountsByCell = [:]
        for entry in snapshot.entries {
            deltas[entry.key] = entry.delta
            adjustCellCount(entry.delta.cell, by: 1)
        }
        globalValues = [:]
        for entry in snapshot.globals {
            globalValues[entry.key] = entry.value
        }
        allocator = GeneratedReferenceAllocator(nextSequence: snapshot.nextGeneratedSequence)
        changeJournal.removeAll()
        onMutation?(nil, changeJournal.nextSequence)
        onGlobalMutation?(changeJournal.nextSequence)
    }

    // MARK: - Dirty tracking

    /// Number of references deviating from plugin data.
    public var dirtyCount: Int {
        deltas.count
    }

    public func isDirty(_ key: ReferenceKey) -> Bool {
        deltas[key] != nil
    }

    /// Dirty references last mutated under `cell`.
    public func dirtyCount(in cell: CellSceneLocation) -> Int {
        dirtyCountsByCell[cell] ?? 0
    }

    /// Every cell with at least one dirty reference, and its count.
    public var dirtyCountsByCellLocation: [CellSceneLocation: Int] {
        dirtyCountsByCell
    }

    /// Dirty references not attributed to any cell, which is the difference
    /// between `dirtyCount` and the sum of the per-cell counts.
    public var unattributedDirtyCount: Int {
        dirtyCount - dirtyCountsByCell.values.reduce(0, +)
    }

    /// Dirty keys in `ReferenceKey` total order.
    public func sortedDirtyKeys() -> [ReferenceKey] {
        deltas.keys.sorted()
    }

    /// Dirty keys last mutated under `cell`, in `ReferenceKey` total order.
    public func sortedDirtyKeys(in cell: CellSceneLocation) -> [ReferenceKey] {
        deltas.filter { $0.value.cell == cell }.keys.sorted()
    }

    // MARK: - Journal

    /// Retained journal entries, oldest first.
    public var journalEntries: [WorldStateJournalEntry] {
        changeJournal.entries
    }

    /// Retained entry cap, as configured at construction.
    public var journalCapacity: Int {
        changeJournal.capacity
    }

    /// Entries dropped because the window was full.
    public var droppedJournalEntryCount: Int {
        changeJournal.droppedCount
    }

    /// Sequence number the next journalled mutation will carry.
    public var nextJournalSequence: UInt64 {
        changeJournal.nextSequence
    }

    /// Journal entries at or after `sequence`, for a consumer that processed
    /// everything below it. Entries already dropped are simply absent, which
    /// `droppedJournalEntryCount` lets the caller detect.
    public func journalEntries(since sequence: UInt64) -> [WorldStateJournalEntry] {
        changeJournal.entries.filter { $0.sequence >= sequence }
    }

    /// Empties the retained window without touching state or sequence numbers.
    public func clearJournal() {
        changeJournal.removeAll()
    }

    // MARK: - Generated references

    /// Mints the next `ReferenceKey.generated` value. The store owns the
    /// allocator because generated identity outlives every cell, exactly like
    /// the deltas beside it.
    public func allocateGeneratedKey() -> ReferenceKey {
        allocator.allocate()
    }

    /// The allocator's next sequence number, which is the whole of its state.
    public var nextGeneratedSequence: UInt64 {
        allocator.nextSequence
    }

    // MARK: - Snapshot

    /// Deterministic view of the current state, in `ReferenceKey` order. The only
    /// part that crosses threads; its `sequence` lets a built cell be checked later.
    public func snapshot() -> WorldStateSnapshot {
        WorldStateSnapshot(
            entries: sortedDirtyKeys().compactMap { key in
                guard let delta = deltas[key] else { return nil }
                return WorldStateSnapshotEntry(key: key, delta: delta)
            },
            nextGeneratedSequence: allocator.nextSequence,
            globals: sortedOverriddenGlobalKeys().compactMap { key in
                guard let value = globalValues[key] else { return nil }
                return WorldStateGlobalSnapshotEntry(key: key, value: value)
            },
            sequence: changeJournal.nextSequence
        )
    }

    // MARK: - Private

    private func adjustCellCount(_ cell: CellSceneLocation?, by amount: Int) {
        guard let cell else { return }
        let updated = (dirtyCountsByCell[cell] ?? 0) + amount
        if updated <= 0 {
            dirtyCountsByCell.removeValue(forKey: cell)
        } else {
            dirtyCountsByCell[cell] = updated
        }
    }
}
