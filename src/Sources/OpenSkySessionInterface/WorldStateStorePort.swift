public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyQuestsInterface
public import OpenSkyWorldState

/// What the world adapters use of `WorldStateStore`.
public protocol WorldStateStorePort: AnyObject {
    func allocateGeneratedKey() -> ReferenceKey
    func component<Component: WorldStateComponent>(
        _ type: Component.Type,
        for key: ReferenceKey
    ) -> Component?
    func delta(for key: ReferenceKey) -> ReferenceStateDelta?
    var deltaRevision: UInt64 { get }
    func derived<Value>(_ type: Value.Type, from source: AnyObject, build: () -> Value) -> Value
    func frozenLeveledLevel(of key: ReferenceKey) -> Int?
    @discardableResult func incrementMiscStat(_ name: String, by amount: Int32) -> Bool
    var journalEntries: [WorldStateJournalEntry] { get }
    func journalEntries(since sequence: UInt64) -> [WorldStateJournalEntry]
    func leveledRoll(
        of key: ReferenceKey,
        base: FormID,
        with roller: LeveledListRoller
    ) -> LeveledRoll
    var miscStats: MiscStatsState { get }
    var nextJournalSequence: UInt64 { get }
    @discardableResult func reset(_ kind: WorldStateComponentKind, for key: ReferenceKey) -> Bool
    @discardableResult func reset(_ key: ReferenceKey) -> Bool
    func resolvedState(for entry: RuntimeReferenceEntry) -> ReferenceState
    func restore(from snapshot: WorldStateSnapshot)
    func revision(of kinds: [WorldStateComponentKind]) -> UInt64
    @discardableResult func set(
        _ component: some WorldStateComponent,
        for key: ReferenceKey,
        in cell: CellSceneLocation?
    ) -> Bool
    func setEyeTexture(_ set: FormID, for actor: ReferenceKey, in cell: CellSceneLocation)
    func snapshot() -> WorldStateSnapshot
    func sortedDirtyKeys() -> [ReferenceKey]
    func sortedDirtyKeys(in cell: CellSceneLocation) -> [ReferenceKey]
}

/// The default arguments a protocol requirement cannot carry.
extension WorldStateStorePort {
    @discardableResult public func incrementMiscStat(_ name: String) -> Bool {
        incrementMiscStat(name, by: 1)
    }

    @discardableResult public func set(
        _ component: some WorldStateComponent,
        for key: ReferenceKey
    ) -> Bool {
        set(component, for: key, in: nil)
    }
}
