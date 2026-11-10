public import OpenSkyCombatInterface
public import OpenSkyConditions
public import OpenSkyDialogueInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyQuestsInterface
public import OpenSkyScriptingInterface
public import OpenSkyWorldState

/// What the world adapters use of `PapyrusWorldStateBridge`.
public protocol PapyrusWorldStateBridgePort: AnyObject, DialogueFragmentDispatching,
    SceneFragmentDispatching
{
    @discardableResult func activate(
        _ target: ReferenceKey,
        by activator: ReferenceKey,
        togglesOpen: Bool
    ) -> PapyrusActivationOutcome
    func actorFlags(of key: ReferenceKey, record: ActorBase.Flags?) -> ActorBase.Flags?
    @discardableResult func addSpell(_ spell: ReferenceKey, to actor: ReferenceKey) -> Bool
    @discardableResult func attachRunningQuestScripts() -> Int
    @discardableResult func attachScripts(ofQuest id: FormID) -> Int
    func baseObject(of key: ReferenceKey) -> FormID?
    @discardableResult func castSpell(
        _ spell: ReferenceKey,
        from source: ReferenceKey,
        at target: ReferenceKey?,
        blame: ReferenceKey?
    ) -> Bool
    func formHasKeyword(_ form: ReferenceKey, keyword: ReferenceKey) -> Bool?
    var formIDResolver: FormIDResolver? { get }
    var gameNatives: PapyrusGameNatives { get set }
    func isHostile(_ actor: ReferenceKey, toward other: ReferenceKey) -> Bool?
    func isInFaction(_ actor: ReferenceKey, faction: ReferenceKey) -> Bool?
    var isPlayerSunGazing: Bool { get }
    @discardableResult func killActor(_ key: ReferenceKey, killer: ReferenceKey?) -> Bool
    func localFormID(of key: ReferenceKey) -> FormID?
    func lockState(for key: ReferenceKey) -> ReferenceLockState?
    func markLocationCleared(_ location: ReferenceKey, playsMusic: Bool)
    var menus: (any PapyrusMenuBridge)? { get }
    func noteStolenValue(_ value: Int64, from faction: ReferenceKey, witnessed: Bool)
    func placement(of key: ReferenceKey) -> ReferencePlacement?
    var playerControlLocks: PlayerControlLocks { get }
    func publishFactionReactions()
    func publishLeveledEdits()
    var questRuntime: (any QuestAccess)? { get }
    /// Sends `OnRead` to the scripts on base item `base`.
    func queueItemRead(base: ReferenceKey)
    @discardableResult func queuePackageEvent(
        slot: UInt32,
        package: FormID,
        actor: ReferenceKey
    ) -> Int
    @discardableResult func queueStoryStartEvent(quest id: FormID, event: StoryEventData) -> Int
    func recordHit(_ hit: ScriptHitEvent, targetWasHostile: Bool)
    func recordKill(victim: ReferenceKey, killer: ReferenceKey?)
    func referenceKey(forFormID formID: FormID) -> ReferenceKey?
    func referenceState(for key: ReferenceKey) -> ReferenceState?
    func relationshipRank(of actor: ReferenceKey, toward other: ReferenceKey) -> Int8??
    func relocate(_ key: ReferenceKey, to location: CellSceneLocation)
    @discardableResult func removeSpell(_ spell: ReferenceKey, from actor: ReferenceKey) -> Bool
    @discardableResult func resurrectActor(_ key: ReferenceKey) -> Bool
    @discardableResult func runPackageFragment(
        of package: Package,
        slot: UInt32,
        actor: ReferenceKey
    ) -> Bool
    @discardableResult func runPerkFragment(
        of perk: Perk,
        key: ReferenceKey,
        index: UInt16,
        activation: PerkFragmentActivation
    ) -> Bool
    func scriptedState(of key: ReferenceKey) -> ScriptedReferenceState
    func scriptedStateResolution() -> ScriptedStateConditionResolution
    @discardableResult func setQuestStage(_ stage: UInt16, for key: ReferenceKey) throws -> Bool
    var silentDeath: ReferenceKey? { get }
    func spawnReference(of base: ReferenceKey, at anchor: ReferenceKey) -> ReferenceKey?
    @discardableResult func startActorCombat(_ key: ReferenceKey, target: ReferenceKey) -> Bool
    @discardableResult func stopActorCombat(_ key: ReferenceKey) -> Bool
    func stopQuest(for key: ReferenceKey) throws
    func updateScriptedState(of key: ReferenceKey, _ change: (inout ScriptedReferenceState) -> Void)
    @discardableResult func write(_ component: WorldStateComponentValue, for key: ReferenceKey)
        -> Bool
}

/// The default arguments a protocol requirement cannot carry.
extension PapyrusWorldStateBridgePort {
    @discardableResult public func actorFlags(of key: ReferenceKey) -> ActorBase.Flags? {
        actorFlags(of: key, record: nil)
    }
}

extension PapyrusWorldStateBridgePort {
    public func questKey(editorID: String) -> ReferenceKey? {
        questRuntime?.quests.key(editorID: editorID)
    }
}
