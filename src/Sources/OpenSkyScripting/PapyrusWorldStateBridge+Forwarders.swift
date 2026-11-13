// The bridge protocol requirements, each answered by the part that owns it.

import Foundation
public import OpenSkyCombatInterface
public import OpenSkyConditions
import OpenSkyCrimeInterface
public import OpenSkyDialogueInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyQuestsInterface
public import OpenSkyScriptingInterface
import OpenSkyWorldInterface
public import OpenSkyWorldState

extension PapyrusWorldStateBridge {
    public var questBridge: any PapyrusWorldQuestBridge {
        questScripts
    }

    public var actorBridge: any PapyrusWorldActorBridge {
        actorValues
    }

    public var magicBridge: any PapyrusWorldMagicBridge {
        spellEffects
    }

    public var crimeBridge: any PapyrusWorldCrimeBridge {
        crime
    }

    public var factionBridge: any PapyrusWorldFactionBridge {
        factions
    }

    public var guardBridge: any PapyrusWorldGuardBridge {
        guards
    }

    public func stopQuest(for key: ReferenceKey) throws {
        try questScripts.stopQuest(for: key)
    }

    @discardableResult
    public func setQuestStage(_ stage: UInt16, for key: ReferenceKey) throws -> Bool {
        try questScripts.setQuestStage(stage, for: key)
    }

    @discardableResult
    public func startActorCombat(_ key: ReferenceKey, target: ReferenceKey) -> Bool {
        actorValues.startActorCombat(key, target: target)
    }

    @discardableResult
    public func stopActorCombat(_ key: ReferenceKey) -> Bool {
        actorValues.stopActorCombat(key)
    }

    @discardableResult
    public func killActor(_ key: ReferenceKey, killer: ReferenceKey?) -> Bool {
        actorValues.killActor(key, killer: killer)
    }

    @discardableResult
    public func addSpell(_ spell: ReferenceKey, to actor: ReferenceKey) -> Bool {
        spellEffects.addSpell(spell, to: actor)
    }

    @discardableResult
    public func removeSpell(_ spell: ReferenceKey, from actor: ReferenceKey) -> Bool {
        spellEffects.removeSpell(spell, from: actor)
    }

    @discardableResult
    public func castSpell(
        _ spell: ReferenceKey, from source: ReferenceKey, at target: ReferenceKey?,
        blame: ReferenceKey?
    ) -> Bool {
        spellEffects.castSpell(spell, from: source, at: target, blame: blame)
    }

    public func isInFaction(_ actor: ReferenceKey, faction: ReferenceKey) -> Bool? {
        factions.isInFaction(actor, faction: faction)
    }

    public func relationshipRank(of actor: ReferenceKey, toward other: ReferenceKey) -> Int8?? {
        factions.relationshipRank(of: actor, toward: other)
    }

    public func isHostile(_ actor: ReferenceKey, toward other: ReferenceKey) -> Bool? {
        factions.isHostile(actor, toward: other)
    }

    public func formListEntries(of key: ReferenceKey) -> [ReferenceKey?]? {
        scriptState.formListEntries(of: key)
    }

    public func formHasKeyword(_ form: ReferenceKey, keyword: ReferenceKey) -> Bool? {
        formLists.formHasKeyword(form, keyword: keyword)
    }

    @discardableResult
    public func actorFlags(
        of key: ReferenceKey, record: ActorBase.Flags? = nil
    ) -> ActorBase.Flags? {
        actorValues.actorFlags(of: key, record: record)
    }

    public func placement(of key: ReferenceKey) -> ReferencePlacement? {
        referencePlacement.placement(of: key)
    }

    public func spawnReference(of base: ReferenceKey, at anchor: ReferenceKey) -> ReferenceKey? {
        referencePlacement.spawnReference(of: base, at: anchor)
    }

    public func relocate(_ key: ReferenceKey, to location: CellSceneLocation) {
        referencePlacement.relocate(key, to: location)
    }

    public func queueItemRead(base: ReferenceKey) {
        inventoryEvents.queueItemRead(base: base)
    }

    public func scriptedState(of key: ReferenceKey) -> ScriptedReferenceState {
        scriptState.scriptedState(of: key)
    }

    public func scriptedStateResolution() -> ScriptedStateConditionResolution {
        scriptState.scriptedStateResolution()
    }

    public func publishFactionReactions() {
        scriptState.publishFactionReactions()
    }

    public func updateScriptedState(
        of key: ReferenceKey, _ change: (inout ScriptedReferenceState) -> Void
    ) {
        scriptState.updateScriptedState(of: key, change)
    }

    public func publishLeveledEdits() {
        leveledEdits.publishLeveledEdits()
    }

    public func recordKill(victim: ReferenceKey, killer: ReferenceKey?) {
        recordReads.recordKill(victim: victim, killer: killer)
    }

    public func markLocationCleared(_ location: ReferenceKey, playsMusic: Bool) {
        recordReads.markLocationCleared(location, playsMusic: playsMusic)
    }

    public func recordHit(_ hit: ScriptHitEvent, targetWasHostile: Bool) {
        recordReads.recordHit(hit, targetWasHostile: targetWasHostile)
    }

    public var isPlayerSunGazing: Bool {
        sunGaze.isPlayerSunGazing
    }

    public var playerControlLocks: PlayerControlLocks {
        stateLinks.playerControlLocks
    }

    public func noteStolenValue(_ value: Int64, from faction: ReferenceKey, witnessed: Bool) {
        referenceRules.noteStolenValue(value, from: faction, witnessed: witnessed)
    }

    @discardableResult
    public func attachRunningQuestScripts() -> Int {
        questScripts.attachRunningQuestScripts()
    }

    @discardableResult
    public func attachScripts(ofQuest id: FormID) -> Int {
        questScripts.attachScripts(ofQuest: id)
    }

    @discardableResult
    public func queuePackageEvent(slot: UInt32, package: FormID, actor: ReferenceKey) -> Int {
        storyEvents.queuePackageEvent(slot: slot, package: package, actor: actor)
    }

    @discardableResult
    public func queueStoryStartEvent(quest id: FormID, event: StoryEventData) -> Int {
        storyEvents.queueStoryStartEvent(quest: id, event: event)
    }

    @discardableResult
    public func resurrectActor(_ key: ReferenceKey) -> Bool {
        actorValues.resurrectActor(key)
    }

    @discardableResult
    public func runPackageFragment(of package: Package, slot: UInt32, actor: ReferenceKey) -> Bool {
        storyEvents.runPackageFragment(of: package, slot: slot, actor: actor)
    }

    @discardableResult
    public func runPerkFragment(
        of perk: Perk, key: ReferenceKey, index: UInt16, activation: PerkFragmentActivation
    ) -> Bool {
        storyEvents.runPerkFragment(of: perk, key: key, index: index, activation: activation)
    }

    public var gameNatives: PapyrusGameNatives {
        get { natives.game }
        set { natives.game = newValue }
    }

    public var menus: (any PapyrusMenuBridge)? {
        ports.menus
    }

    public func referenceState(for key: ReferenceKey) -> ReferenceState? {
        referenceReads.referenceState(for: key)
    }

    public func linkedReferences(of key: ReferenceKey) -> [LinkedReference] {
        referenceReads.linkedReferences(of: key)
    }

    public func baseObject(of key: ReferenceKey) -> FormID? {
        referenceReads.baseObject(of: key)
    }

    @discardableResult
    public func write(_ component: WorldStateComponentValue, for key: ReferenceKey) -> Bool {
        activations.write(component, for: key)
    }

    @discardableResult
    public func activate(
        _ target: ReferenceKey, by activator: ReferenceKey, togglesOpen: Bool
    ) -> PapyrusActivationOutcome {
        activations.activate(target, by: activator, togglesOpen: togglesOpen)
    }

    public func globalValue(for key: ReferenceKey) -> GlobalValue? {
        globalReads.globalValue(for: key)
    }

    @discardableResult
    public func setGlobal(_ raw: Float, for key: ReferenceKey) -> Bool {
        globalReads.setGlobal(raw, for: key)
    }

    /// The actor an `AttachAshPile` pile stands for; nil for anything else.
    public func ashPileOwner(of key: ReferenceKey) -> ReferenceKey? {
        activations.ashPileOwner(of: key)
    }

    public func localFormID(of key: ReferenceKey) -> FormID? {
        referenceReads.localFormID(of: key)
    }

    public func referenceKey(forFormID formID: FormID) -> ReferenceKey? {
        referenceReads.referenceKey(forFormID: formID)
    }

    public func placedReference(for key: ReferenceKey) -> PlacedReference? {
        referenceReads.placedReference(for: key)
    }

    public func lockState(for key: ReferenceKey) -> ReferenceLockState? {
        referenceReads.lockState(for: key)
    }

    /// The actor `KillSilent` is killing, so the host skips the story-manager `KILL` event.
    public var silentDeath: ReferenceKey? {
        runState.silentDeath
    }

    public var dialogueFragments: any DialogueFragmentDispatching {
        fragments
    }

    public var sceneFragments: any SceneFragmentDispatching {
        fragments
    }
}
