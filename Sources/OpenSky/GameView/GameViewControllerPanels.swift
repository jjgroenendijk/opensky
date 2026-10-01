// One-line forwards from the panel protocols to the coordinators and the menu
// controllers `GameViewController` holds. The logic lives behind them
// (docs/engine/coordinators.md).

import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyProgression
import OpenSkyQuests
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldState

/// The Combat & Physics panel reads the coordinator.
extension GameViewController: MeleeCombatControlProviding {
    var meleeCombatSnapshot: MeleeCombatSnapshot {
        combat.meleeCombatSnapshot
    }

    var isWeaponDrawn: Bool {
        get { combat.isWeaponDrawn }
        set { combat.isWeaponDrawn = newValue }
    }

    @discardableResult
    func requestMeleeAttack() -> String {
        combat.requestMeleeAttack()
    }

    func clearMeleeTrace() {
        combat.clearMeleeTrace()
    }
}

extension GameViewController: ArcheryControlProviding {
    var archerySnapshot: ArcherySnapshot {
        combat.archerySnapshot
    }

    @discardableResult
    func spawnDevProjectile() -> String {
        combat.spawnDevProjectile()
    }

    func despawnProjectiles() {
        combat.despawnProjectiles()
    }

    func clearStuckProjectiles() {
        combat.clearStuckProjectiles()
    }

    func clearProjectileTrace() {
        combat.clearProjectileTrace()
    }
}

extension GameViewController: CombatLoopControlProviding {
    var combatLoopSnapshot: CombatLoopSnapshot {
        combat.combatLoopSnapshot
    }

    var selectedActorIsHostile: Bool {
        get { combat.selectedActorIsHostile }
        set { combat.selectedActorIsHostile = newValue }
    }

    var isActorCastingEnabled: Bool {
        get { combat.isActorCastingEnabled }
        set { combat.isActorCastingEnabled = newValue }
    }

    func clearCombatTrace() {
        combat.clearCombatTrace()
    }
}

extension GameViewController: MagicEffectControlProviding {
    var magicEffectControlSnapshot: MagicEffectControlSnapshot {
        magic.magicEffectControlSnapshot
    }

    @discardableResult
    func consumeFirstCarriedMagicItem() -> String {
        magic.consumeFirstCarriedMagicItem()
    }

    @discardableResult
    func dispelPlayerMagicEffects() -> String {
        magic.dispelPlayerMagicEffects()
    }
}

extension GameViewController: CastingControlProviding {
    var castingControlSnapshot: CastingControlSnapshot {
        magic.castingControlSnapshot
    }

    @discardableResult
    func grantPlayerStartSpells() -> String {
        magic.grantPlayerStartSpells()
    }

    @discardableResult
    func readFirstCarriedSpellTome() -> String {
        magic.readFirstCarriedSpellTome()
    }

    @discardableResult
    func selectNextKnownSpell() -> String {
        magic.selectNextKnownSpell()
    }

    @discardableResult
    func readySelectedSpell(in hand: SpellHand) -> String {
        magic.readySelectedSpell(in: hand)
    }

    @discardableResult
    func castReadiedSpell(in hand: SpellHand) -> String {
        magic.castReadiedSpell(in: hand)
    }
}

extension GameViewController: ItemControlProviding {
    var itemControlSnapshot: ItemControlSnapshot {
        inventory.itemControlSnapshot
    }

    @discardableResult
    func takeInteractionTarget() -> String {
        inventory.takeInteractionTarget()
    }

    @discardableResult
    func openInteractionTargetContainer() -> String {
        inventory.openInteractionTargetContainer()
    }

    @discardableResult
    func takeAllFromOpenContainer() -> String {
        inventory.takeAllFromOpenContainer()
    }

    @discardableResult
    func closeOpenContainer() -> String {
        inventory.closeOpenContainer()
    }

    @discardableResult
    func dropPlayerItem(_ item: FormID?, count: Int32) -> String {
        inventory.dropPlayerItem(item, count: count)
    }

    @discardableResult
    func equipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String {
        inventory.equipItem(item, on: target)
    }

    @discardableResult
    func unequipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String {
        inventory.unequipItem(item, on: target)
    }
}

extension GameViewController: InventoryEquipmentControlProviding {
    var inventoryEquipmentInspectionTarget: EquipmentTargetSelector {
        get { inventory.inspectionTarget }
        set { inventory.inspectionTarget = newValue }
    }

    var inventoryEquipmentSnapshot: InventoryEquipmentSnapshot {
        inventory.inventoryEquipmentSnapshot
    }

    @discardableResult
    func grantItem(_ item: FormID, count: Int32, to target: InventoryGrantTarget) -> String {
        inventory.grantItem(item, count: count, to: target)
    }
}

extension GameViewController: InventoryMenuControlProviding {
    var inventoryMenuIsOpen: Bool {
        inventoryMenu.isOpen
    }

    var inventoryMenuMovieEnabled: Bool {
        get { inventoryMenu.movieEnabled }
        set { inventoryMenu.setMovieEnabled(newValue) }
    }

    var inventoryMenuSnapshot: InventoryMenuControlSnapshot {
        inventoryMenu.snapshot
    }

    func openInventoryMenu() {
        inventoryMenu.open()
    }

    func closeInventoryMenu() {
        inventoryMenu.close()
    }

    func sendInventoryMenuInput(_ event: MenuInputEvent) {
        inventoryMenu.route(event)
    }

    func activateInventoryMenuSelection() {
        inventoryMenu.activateSelection()
    }

    func dropInventoryMenuSelection() {
        inventoryMenu.dropSelection()
    }

    func consumeInventoryMenuSelection() {
        inventoryMenu.consumeSelection()
    }
}

extension GameViewController: ContainerMenuControlProviding {
    var containerMenuIsOpen: Bool {
        containerMenu.isOpen
    }

    var containerMenuMode: ContainerMenuModel.Mode {
        get { containerMenu.mode }
        set { containerMenu.setMode(newValue) }
    }

    var containerMenuMovieEnabled: Bool {
        get { containerMenu.movieEnabled }
        set { containerMenu.setMovieEnabled(newValue) }
    }

    var containerMenuSnapshot: ContainerMenuControlSnapshot {
        containerMenu.snapshot
    }

    func openContainerMenu() {
        containerMenu.open()
    }

    func closeContainerMenu() {
        containerMenu.close()
    }

    func sendContainerMenuInput(_ event: MenuInputEvent) {
        containerMenu.route(event)
    }

    func switchContainerMenuSide() {
        containerMenu.switchSide()
    }

    func activateContainerMenuSelection() {
        containerMenu.activateSelection()
    }

    func takeAllFromContainerMenu() {
        containerMenu.takeAll()
    }

    @discardableResult
    func selectContainerMenuMerchant(_ reference: FormID) -> String {
        containerMenu.selectMerchant(reference)
    }

    @discardableResult
    func selectContainerMenuMerchantFromInteraction() -> String {
        containerMenu.selectMerchantFromInteraction()
    }
}

extension GameViewController: CrimeFactionControlProviding {
    var crimeFactionSnapshot: CrimeFactionControlSnapshot {
        crime.crimeFactionSnapshot
    }

    var bountyFactionSelection: ReferenceKey? {
        get { crime.bountyFactionSelection }
        set { crime.bountyFactionSelection = newValue }
    }

    var membershipFactionSelection: ReferenceKey? {
        get { crime.membershipFactionSelection }
        set { crime.membershipFactionSelection = newValue }
    }

    var vendorOverrideSelection: ReferenceKey? {
        get { crime.vendorOverrideSelection }
        set { crime.vendorOverrideSelection = newValue }
    }

    @discardableResult
    func modifySelectedBounty(by gold: Int32, violent: Bool) -> String {
        crime.modifySelectedBounty(by: gold, violent: violent)
    }

    @discardableResult
    func clearSelectedBounty() -> String {
        crime.clearSelectedBounty()
    }

    @discardableResult
    func checkGuardConfrontation() -> String {
        crime.checkGuardConfrontation()
    }

    @discardableResult
    func resistArrestWithSelectedFaction() -> String {
        crime.resistArrestWithSelectedFaction()
    }

    @discardableResult
    func selectSocialSubjectFromCrosshair() -> String {
        crime.selectSocialSubjectFromCrosshair()
    }

    @discardableResult
    func selectPlayerAsSocialSubject() -> String {
        crime.selectPlayerAsSocialSubject()
    }

    @discardableResult
    func joinSelectedFaction(rank: Int8) -> String {
        crime.joinSelectedFaction(rank: rank)
    }

    @discardableResult
    func leaveSelectedFaction() -> String {
        crime.leaveSelectedFaction()
    }

    @discardableResult
    func barterWithSocialSubject() -> String {
        crime.barterWithSocialSubject()
    }
}

extension GameViewController: DialogueControlProviding {
    var dialogueSnapshot: DialogueControlSnapshot {
        dialogueMenu.snapshot
    }

    func openDialogue() {
        dialogueMenu.openFromCrosshair()
    }

    func closeDialogue() {
        dialogueMenu.close()
    }

    func sendDialogueInput(_ event: MenuInputEvent) {
        dialogueMenu.route(event)
    }
}

extension GameViewController: DialogueCameraControlProviding {
    var dialogueCameraSnapshot: DialogueCameraSnapshot {
        dialogueCamera.snapshot
    }

    var isDialogueCameraForced: Bool {
        get { dialogueCamera.isForced }
        set { dialogueCamera.setForced(newValue) }
    }

    var dialogueCameraTarget: DialogueCameraTarget {
        get { dialogueCamera.target }
        set { dialogueCamera.setTarget(newValue) }
    }

    var dialogueCameraOverlayEnabled: Bool {
        get { renderer?.dialogueCameraOverlayEnabled ?? false }
        set { renderer?.dialogueCameraOverlayEnabled = newValue }
    }
}

extension GameViewController: JournalControlProviding {
    var journalSnapshot: JournalControlSnapshot {
        journalMenu.snapshot
    }

    var journalQuestEditorID: String {
        get { journal.editorID }
        set { journalMenu.setEditorID(newValue) }
    }

    var journalQuestEditorIDs: [String] {
        journal.questEditorIDs
    }

    func openJournal() {
        journalMenu.open()
    }

    func closeJournal() {
        journalMenu.close()
    }

    func sendJournalInput(_ event: MenuInputEvent) {
        journalMenu.route(event)
    }

    func setJournalShowsCompleted(_ flag: Bool) {
        journalMenu.setShowsCompleted(flag)
    }

    func startSelectedQuest() {
        journalMenu.applied(journal.startSelectedQuest())
    }

    func stopSelectedQuest() {
        journalMenu.applied(journal.stopSelectedQuest())
    }

    func setSelectedQuestStage(_ index: Int) {
        journalMenu.applied(journal.setSelectedQuestStage(index))
    }

    func setSelectedQuestObjective(_ index: Int, displayed: Bool) {
        journalMenu.applied(journal.setSelectedQuestObjective(index, displayed: displayed))
    }

    func journalAliasTable(editorID: String) -> ScriptQuestAliasInspection? {
        scripts.questAliasTable(editorID: editorID)
    }
}

extension GameViewController: ActorValueControlProviding {
    var actorValueControlSnapshot: ActorValueControlSnapshot {
        actorValues.snapshot
    }

    var actorValueTarget: ActorValueTargetSelector {
        get { actorValues.target }
        set { actorValues.target = newValue }
    }

    var actorValueSelection: Int32 {
        get { actorValues.selection }
        set { actorValues.selection = newValue }
    }

    @discardableResult
    func damageSelectedActor(by amount: Float) -> String {
        actorValues.damageSelected(by: amount)
    }

    @discardableResult
    func restoreSelectedActor(by amount: Float) -> String {
        actorValues.restoreSelected(by: amount)
    }

    @discardableResult
    func setSelectedActorValue(to value: Float) -> String {
        actorValues.setSelectedValue(to: value)
    }

    @discardableResult
    func setSelectedActorBase(to value: Float) -> String {
        actorValues.setSelectedBase(to: value)
    }

    @discardableResult
    func restoreSelectedActorFully() -> String {
        actorValues.restoreSelectedFully()
    }

    @discardableResult
    func resetSelectedActorValues() -> String {
        actorValues.resetSelected()
    }
}

extension GameViewController: ProgressionControlProviding {
    var progressionControlSnapshot: ProgressionControlSnapshot {
        progression.snapshot
    }

    var progressionSkillSelection: Int32 {
        get { progression.skillSelection }
        set { progression.selectSkill(newValue) }
    }

    var progressionNodeSelection: UInt32 {
        get { progression.nodeSelection }
        set { progression.nodeSelection = newValue }
    }

    @discardableResult
    func advanceSelectedSkill(byUse amount: Float) -> String {
        progression.advanceSelectedSkill(byUse: amount)
    }

    @discardableResult
    func incrementSelectedSkill() -> String {
        progression.incrementSelectedSkill()
    }

    @discardableResult
    func awardCharacterExperience(_ amount: Float) -> String {
        progression.awardCharacterExperience(amount)
    }

    @discardableResult
    func chooseAttributePick(_ kind: ActorValueKind) -> String {
        progression.chooseAttributePick(kind)
    }

    @discardableResult
    func changePerkPoints(by delta: Int) -> String {
        progression.changePerkPoints(by: delta)
    }

    @discardableResult
    func spendPointOnSelectedPerk() -> String {
        progression.spendPointOnSelectedPerk()
    }

    @discardableResult
    func grantSelectedPerk() -> String {
        progression.grantSelectedPerk()
    }

    @discardableResult
    func revokeSelectedPerk() -> String {
        progression.revokeSelectedPerk()
    }
}

extension GameViewController: RagdollControlProviding {
    var ragdollStatsSnapshot: RagdollStatsSnapshot {
        ragdoll.ragdollStatsSnapshot
    }

    @discardableResult
    func triggerRagdoll() -> Bool {
        ragdoll.triggerRagdoll()
    }

    func setRagdollFrozen(_ frozen: Bool) {
        ragdoll.setRagdollFrozen(frozen)
    }

    func setRagdollSelfCollision(_ enabled: Bool) {
        ragdoll.setRagdollSelfCollision(enabled)
    }

    func clearRagdolls() {
        ragdoll.clearRagdolls()
    }
}

extension GameViewController: PlayerLocomotionControlProviding {
    var playerLocomotionSnapshot: PlayerLocomotionSnapshot {
        player.playerLocomotionSnapshot
    }

    var isSneaking: Bool {
        get { player.isSneaking }
        set { player.isSneaking = newValue }
    }

    var forcedLocomotionGait: LocomotionGait? {
        get { player.forcedLocomotionGait }
        set { player.forcedLocomotionGait = newValue }
    }

    func requestJump() {
        player.requestJump()
    }

    @discardableResult
    func raiseLocomotionEvent(named name: String) -> Bool {
        player.raiseLocomotionEvent(named: name)
    }

    func clearLocomotionTrace() {
        player.clearLocomotionTrace()
    }
}

extension GameViewController: FirstPersonControlProviding {
    var firstPersonSnapshot: FirstPersonSnapshot {
        player.firstPersonSnapshot
    }

    var firstPersonFOVYDegrees: Float {
        get { player.firstPersonFOVYDegrees }
        set { player.firstPersonFOVYDegrees = newValue }
    }

    var firstPersonArmsEnabled: Bool {
        get { player.firstPersonArmsEnabled }
        set { player.firstPersonArmsEnabled = newValue }
    }
}

extension GameViewController: FaceMorphControlProviding {
    var faceMorphSnapshot: FaceMorphControlSnapshot {
        faceMorphs.faceMorphSnapshot
    }

    func setFaceMorphWeight(_ weight: Float, target: String) {
        faceMorphs.setFaceMorphWeight(weight, target: target)
    }

    func resetFaceMorphWeights() {
        faceMorphs.resetFaceMorphWeights()
    }
}

extension GameViewController: AIOverlayControlProviding {
    var navmeshOverlayEnabled: Bool {
        get { renderer?.navmeshOverlayEnabled ?? false }
        set { renderer?.navmeshOverlayEnabled = newValue }
    }

    var pathOverlayEnabled: Bool {
        get { renderer?.pathOverlayEnabled ?? false }
        set { renderer?.pathOverlayEnabled = newValue }
    }

    var detectionOverlayEnabled: Bool {
        get { renderer?.detectionOverlayEnabled ?? false }
        set { renderer?.detectionOverlayEnabled = newValue }
    }

    var aiOverlaySnapshot: AIOverlayControlSnapshot {
        AIOverlayControlSnapshot(
            navmeshOverlayEnabled: navmeshOverlayEnabled,
            pathOverlayEnabled: pathOverlayEnabled,
            detectionOverlayEnabled: detectionOverlayEnabled,
            stats: renderer?.lastWorldOverlayDrawStats ?? WorldOverlayDrawStats()
        )
    }
}

extension GameViewController: AINavigationControlProviding {
    var aiNavigationSnapshot: AINavigationSnapshot {
        aiNavigation.aiNavigationSnapshot
    }

    var selectedAIActor: ReferenceKey? {
        get { aiNavigation.selectedAIActor }
        set { aiNavigation.selectedAIActor = newValue }
    }

    var selectedAIActorIsHostile: Bool {
        get { aiNavigation.selectedAIActorIsHostile }
        set { aiNavigation.selectedAIActorIsHostile = newValue }
    }

    func selectAIActorFromCrosshair() {
        aiNavigation.selectAIActorFromCrosshair()
    }

    func moveSelectedAIActorToCrosshair() {
        aiNavigation.moveSelectedAIActorToCrosshair()
    }

    func stopSelectedAIActor() {
        aiNavigation.stopSelectedAIActor()
    }

    func reevaluateSelectedAIActorPackage() {
        aiNavigation.reevaluateSelectedAIActorPackage()
    }
}

extension GameViewController: PerceptionControlProviding {
    var perceptionSnapshot: PerceptionControlSnapshot {
        perception.perceptionSnapshot
    }

    func perceptionLines(for actor: ReferenceKey) -> [String] {
        perception.perceptionLines(for: actor)
    }
}
