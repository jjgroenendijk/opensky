// Mutable world state (issue #159, roadmap item 10.1.2): the one place runtime
// deviations from plugin data live, and the substrate Papyrus (M11), inventory
// (M12) and quests (M13) mutate.
//
// Scope note: this issue owns storage, dirty tracking, reset, the change
// journal and the snapshot. Applying deltas during a cell build is #160,
// serialization is #161 and the sidebar readout is #162.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// Mutable, main-actor-owned store of per-reference runtime state.
///
/// Unlike `WeatherStore`, `SoundRecordStore` and `MusicRecordStore` — immutable
/// read-only indices built once from an `ESMFile` and freely readable from any
/// thread — this store is mutable for the whole life of a session. It is
/// therefore `@MainActor`, owned alongside `CellStreamer`, and holds no locks:
/// the only thing that crosses to the serial cell-build queue is the
/// `WorldStateSnapshot` value returned by `snapshot()`.
///
/// Failure model: no operation on this store throws. Mutating an unknown key is
/// not an error, because a reference need not be resident, or even plugin
/// defined, for state to be recorded against it — a script may disable an
/// object in a cell that has never been loaded. Resetting a clean reference is
/// likewise a no-op that reports `false` rather than failing. This is runtime
/// state, not file parsing; there is no malformed input to reject.
///
/// Baselines are never stored. A caller that wants the effective state of a
/// reference passes the `RuntimeReferenceEntry` from the #158 index to
/// `resolvedState(for:)`, which re-derives the plugin default from the decoded
/// record every time, so a reset genuinely restores whatever the record now
/// says.
@MainActor
final class WorldStateStore {
    /// Per-reference deltas. Only dirty references have an entry: clearing the
    /// last component removes the key entirely, which is what keeps
    /// `dirtyCount` honest.
    private var deltas: [ReferenceKey: ReferenceStateDelta] = [:]
    /// Runtime global-variable overrides (issue #165), keyed by the GLOB
    /// record's session-stable key. A sibling map rather than a component on a
    /// reference: a global is not placed anywhere, has no cell, and must not
    /// drag a cell rebuild behind it when it changes.
    private var globalValues: [ReferenceKey: GlobalValue] = [:]
    /// Dirty reference count per cell, maintained incrementally so a sidebar
    /// readout costs a dictionary lookup rather than a scan.
    private var dirtyCountsByCell: [CellSceneLocation: Int] = [:]
    private var changeJournal: WorldStateJournal
    private var allocator: GeneratedReferenceAllocator

    /// Fires once per journalled mutation with the cell the mutation was
    /// attributed to (nil when it was not attributed to any cell) and the
    /// journal sequence a snapshot taken immediately afterwards would carry.
    ///
    /// This is how `CellStreamer` learns that a resident scene no longer
    /// matches the store (issue #160). It deliberately carries no payload
    /// beyond the location and the sequence: the streamer rebuilds whole
    /// cells from plugin bytes plus a fresh snapshot rather than patching
    /// individual instances, so it needs to know only that something changed
    /// and how recently.
    var onMutation: ((CellSceneLocation?, UInt64) -> Void)?

    /// Fires once per journalled global mutation with the journal sequence a
    /// snapshot taken immediately afterwards would carry.
    ///
    /// Deliberately separate from `onMutation`, which rebuilds cells. A global
    /// is not part of any cell's geometry, and a game clock ticking a global
    /// once a frame through `onMutation` would rebuild the whole resident grid
    /// every frame. Consumers of global values — the weather chance selection
    /// (issue #165), conditions (#251), the clock (#164) — refresh their
    /// `GlobalResolution` from here instead.
    var onGlobalMutation: ((UInt64) -> Void)?

    /// - Parameters:
    ///   - journalCapacity: retained change-journal entries; see
    ///     `WorldStateJournal.defaultCapacity`.
    ///   - allocator: generated-key allocator to adopt, for a restored session
    ///     that must resume its sequence.
    init(
        journalCapacity: Int = WorldStateJournal.defaultCapacity,
        allocator: GeneratedReferenceAllocator = GeneratedReferenceAllocator()
    ) {
        changeJournal = WorldStateJournal(capacity: journalCapacity)
        self.allocator = allocator
    }

    // MARK: - Reading components

    /// The runtime override in `type`'s slot for `key`, or nil when that slot
    /// still matches the plugin.
    func component<Component: WorldStateComponent>(
        _ type: Component.Type,
        for key: ReferenceKey
    ) -> Component? {
        deltas[key]?.component(type)
    }

    /// Every delta recorded for `key`, or nil when the reference is clean.
    func delta(for key: ReferenceKey) -> ReferenceStateDelta? {
        deltas[key]
    }

    /// `entry`'s plugin baseline with this store's deltas applied.
    func resolvedState(for entry: RuntimeReferenceEntry) -> ReferenceState {
        ReferenceState(baseline: entry).applying(deltas[entry.key])
    }

    // MARK: - Writing components

    /// Records `component` for `key`, attributing it to `cell`.
    ///
    /// Writing a value equal to the one already stored is a no-op: nothing is
    /// journalled and `false` comes back. Writing a value that happens to equal
    /// the plugin default still marks the reference dirty, because the store
    /// has no record index to compare against — use `reset(_:for:)` to go back
    /// to the default.
    ///
    /// - Returns: true when the stored state changed.
    @discardableResult
    func set(
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
    func reset(_ kind: WorldStateComponentKind, for key: ReferenceKey) -> Bool {
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
    /// `WorldStateComponentKind.allCases` order so the log stays deterministic.
    ///
    /// - Returns: true when the reference was dirty.
    @discardableResult
    func reset(_ key: ReferenceKey) -> Bool {
        guard let delta = deltas[key] else { return false }
        for kind in delta.sortedKinds {
            reset(kind, for: key)
        }
        return true
    }

    /// Drops every delta in the store. Journal sequence numbering continues,
    /// because these resets did happen.
    func resetAll() {
        for key in sortedDirtyKeys() {
            reset(key)
        }
    }

    // MARK: - Global variables

    /// Runtime override for a global, or nil when it still holds its plugin
    /// default. Callers wanting the effective value — default included — go
    /// through `globalResolution(defaults:)` instead.
    func globalValue(for key: ReferenceKey) -> GlobalValue? {
        globalValues[key]
    }

    /// Writes `value` to a global, coercing it onto the declared type.
    ///
    /// A short or long global rounds (see `Global.ValueType.coerce`), so
    /// writing 3.7 to a short and reading it back yields 4, not 3.7. Writing
    /// the value that is already stored is a no-op and reports `false`. Writing
    /// a value that happens to equal the plugin default still counts as an
    /// override, exactly as with reference components: use `resetGlobal` to go
    /// back to the default.
    ///
    /// - Returns: true when the stored value changed.
    @discardableResult
    func setGlobal(_ value: GlobalValue, for key: ReferenceKey) -> Bool {
        guard globalValues[key] != value else { return false }
        let previous = globalValues[key]
        globalValues[key] = value
        changeJournal.recordGlobal(key: key, oldValue: previous, newValue: value)
        onGlobalMutation?(changeJournal.nextSequence)
        return true
    }

    /// Writes a raw number to a global of declared type `type`.
    @discardableResult
    func setGlobal(_ raw: Float, type: Global.ValueType, for key: ReferenceKey) -> Bool {
        setGlobal(GlobalValue(type: type, rawValue: raw), for: key)
    }

    /// Writes a raw number to the global `id` names, taking the declared type
    /// and the session-stable key from `defaults`.
    ///
    /// - Returns: false when `defaults` defines no such global, as well as when
    ///   the write is a no-op.
    @discardableResult
    func setGlobal(_ raw: Float, formID id: FormID, defaults: GlobalStore) -> Bool {
        guard let global = defaults.global(id), let key = defaults.key(for: id) else {
            return false
        }
        return setGlobal(raw, type: global.valueType, for: key)
    }

    /// Drops a global's override, restoring its plugin default.
    ///
    /// - Returns: true when an override was actually removed.
    @discardableResult
    func resetGlobal(for key: ReferenceKey) -> Bool {
        guard let previous = globalValues.removeValue(forKey: key) else { return false }
        changeJournal.recordGlobal(key: key, oldValue: previous, newValue: nil)
        onGlobalMutation?(changeJournal.nextSequence)
        return true
    }

    /// Drops every global override, in `ReferenceKey` total order so the
    /// journal stays deterministic.
    func resetAllGlobals() {
        for key in sortedOverriddenGlobalKeys() {
            resetGlobal(for: key)
        }
    }

    /// Number of globals deviating from plugin data.
    var overriddenGlobalCount: Int {
        globalValues.count
    }

    /// Overridden global keys in `ReferenceKey` total order.
    func sortedOverriddenGlobalKeys() -> [ReferenceKey] {
        globalValues.keys.sorted()
    }

    /// Retained global journal entries, oldest first.
    var globalJournalEntries: [WorldStateGlobalJournalEntry] {
        changeJournal.globalEntries
    }

    /// Global journal entries dropped because the window was full.
    var droppedGlobalJournalEntryCount: Int {
        changeJournal.droppedGlobalCount
    }

    /// The lookup seam conditions (#251), the game clock (#164) and weather
    /// chance selection read global values through: this session's overrides
    /// over `defaults`' plugin values.
    func globalResolution(defaults: GlobalStore?) -> GlobalResolution {
        GlobalResolution(defaults: defaults, overrides: globalValues)
    }

    // MARK: - Restoring a saved session

    /// Replaces every delta in the store with `snapshot`'s entries and resumes
    /// the generated-key allocator at `snapshot.nextGeneratedSequence`, which
    /// is how a decoded `OpenSkySaveFile` becomes live state (issue #162).
    ///
    /// Journal semantics: the replay records no entries and does not advance
    /// sequence numbering, because the mutations it replays already happened,
    /// in the session that wrote the save. The retained window is cleared
    /// instead, so the readout does not mix this session's history with a
    /// restored world it no longer describes. `droppedJournalEntryCount` is
    /// untouched for the same reason `clearJournal()` leaves it alone.
    ///
    /// Because nothing is journalled, `snapshot()` taken straight afterwards
    /// equals the snapshot passed in: `WorldStateSnapshot` equality covers the
    /// entries and the allocator position and deliberately ignores `sequence`.
    ///
    /// One unattributed mutation is announced through `onMutation` so every
    /// resident cell rebuilds against the restored state. `CellStreamer` queues
    /// a rebuild for each resident cell on an unattributed mutation regardless
    /// of sequence, so the world catches up even though the sequence did not
    /// move.
    func restore(from snapshot: WorldStateSnapshot) {
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
    var dirtyCount: Int {
        deltas.count
    }

    func isDirty(_ key: ReferenceKey) -> Bool {
        deltas[key] != nil
    }

    /// Dirty references last mutated under `cell`.
    func dirtyCount(in cell: CellSceneLocation) -> Int {
        dirtyCountsByCell[cell] ?? 0
    }

    /// Every cell with at least one dirty reference, and its count.
    var dirtyCountsByCellLocation: [CellSceneLocation: Int] {
        dirtyCountsByCell
    }

    /// Dirty references not attributed to any cell, which is the difference
    /// between `dirtyCount` and the sum of the per-cell counts.
    var unattributedDirtyCount: Int {
        dirtyCount - dirtyCountsByCell.values.reduce(0, +)
    }

    /// Dirty keys in `ReferenceKey` total order.
    func sortedDirtyKeys() -> [ReferenceKey] {
        deltas.keys.sorted()
    }

    /// Dirty keys last mutated under `cell`, in `ReferenceKey` total order.
    func sortedDirtyKeys(in cell: CellSceneLocation) -> [ReferenceKey] {
        deltas.filter { $0.value.cell == cell }.keys.sorted()
    }

    // MARK: - Journal

    /// Retained journal entries, oldest first.
    var journalEntries: [WorldStateJournalEntry] {
        changeJournal.entries
    }

    /// Retained entry cap, as configured at construction.
    var journalCapacity: Int {
        changeJournal.capacity
    }

    /// Entries dropped because the window was full.
    var droppedJournalEntryCount: Int {
        changeJournal.droppedCount
    }

    /// Sequence number the next journalled mutation will carry.
    var nextJournalSequence: UInt64 {
        changeJournal.nextSequence
    }

    /// Journal entries at or after `sequence`, for a consumer that processed
    /// everything below it. Entries already dropped are simply absent, which
    /// `droppedJournalEntryCount` lets the caller detect.
    func journalEntries(since sequence: UInt64) -> [WorldStateJournalEntry] {
        changeJournal.entries.filter { $0.sequence >= sequence }
    }

    /// Empties the retained window without touching state or sequence numbers.
    func clearJournal() {
        changeJournal.removeAll()
    }

    // MARK: - Generated references

    /// Mints the next `ReferenceKey.generated` value. The store owns the
    /// allocator because generated identity outlives every cell, exactly like
    /// the deltas beside it.
    func allocateGeneratedKey() -> ReferenceKey {
        allocator.allocate()
    }

    /// The allocator's next sequence number, which is the whole of its state.
    var nextGeneratedSequence: UInt64 {
        allocator.nextSequence
    }

    // MARK: - Snapshot

    /// Deterministic, immutable view of the current state.
    ///
    /// Entries are ordered by `ReferenceKey`'s total order, so the result
    /// depends only on the end state and not on the order the mutations
    /// arrived in. This value is the only part of the store that crosses to
    /// another thread.
    ///
    /// The journal sequence travels with it as `WorldStateSnapshot.sequence`,
    /// so a cell built off this value can be compared against later state
    /// without the builder ever touching the store.
    func snapshot() -> WorldStateSnapshot {
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
