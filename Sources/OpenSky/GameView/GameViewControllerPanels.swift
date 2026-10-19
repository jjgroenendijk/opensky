// One-line forwards from the panel protocols to the coordinators and the menu
// controllers `GameViewController` holds. The logic lives behind them
// (docs/engine/coordinators.md).

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAgentControl
import OpenSkyCells
import OpenSkyCrime
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyRendering
import OpenSkySave
import OpenSkyScriptingInterface
import OpenSkyWorld

/// The Combat & Physics panel reads the coordinator.
extension GameViewController: ItemControlProviding {
    var itemControlSnapshot: ItemControlSnapshot {
        inventory.itemControlSnapshot
    }

    @discardableResult
    func takeInteractionTarget() -> ItemActionOutcome {
        inventory.takeInteractionTarget()
    }

    @discardableResult
    func openInteractionTargetContainer() -> ItemActionOutcome {
        inventory.openInteractionTargetContainer()
    }

    @discardableResult
    func takeAllFromOpenContainer() -> ItemActionOutcome {
        inventory.takeAllFromOpenContainer()
    }

    @discardableResult
    func closeOpenContainer() -> ItemActionOutcome {
        inventory.closeOpenContainer()
    }

    @discardableResult
    func dropPlayerItem(_ item: FormID?, count: Int32) -> ItemActionOutcome {
        inventory.dropPlayerItem(item, count: count)
    }

    @discardableResult
    func equipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> ItemActionOutcome {
        inventoryWorld.run(inventory.equipItem(item, on: target))
    }

    @discardableResult
    func unequipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> ItemActionOutcome {
        inventoryWorld.run(inventory.unequipItem(item, on: target))
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
    func grantItem(
        _ item: FormID,
        count: Int32,
        to target: InventoryGrantTarget
    ) -> GrantActionOutcome {
        inventory.grantItem(item, count: count, to: target)
    }
}

extension GameViewController: CraftingControlProviding {
    var craftingSnapshot: CraftingControlSnapshot {
        inventory.craftingSnapshot
    }

    func openCraftingStation(_ editorID: String) -> CraftingActionOutcome {
        inventory.openCraftingStation(editorID)
    }

    func craftRecipe(_ id: ResolvedFormID) -> CraftingActionOutcome {
        inventory.craftRecipe(id)
    }

    func closeCraftingStation() -> CraftingActionOutcome {
        inventory.closeCraftingStation()
    }

    func forceHarvest() -> ItemActionOutcome {
        inventoryWorld.run(inventory.harvestInteractionTarget())
    }

    func resetHarvest() -> ItemActionOutcome {
        inventoryWorld.run(inventory.resetHarvestOfInteractionTarget())
    }
}

extension GameViewController: AlchemyControlProviding {
    var alchemySnapshot: AlchemyControlSnapshot {
        inventory.alchemySnapshot
    }

    func openAlchemyLab(_ editorID: String) -> CraftingActionOutcome {
        inventory.openAlchemyLab(editorID)
    }

    func toggleAlchemyIngredient(_ id: FormID) -> AlchemyActionOutcome {
        inventory.toggleAlchemyIngredient(id)
    }

    func clearAlchemyIngredients() -> AlchemyActionOutcome {
        inventory.clearAlchemyIngredients()
    }

    func brewChosenIngredients() -> AlchemyActionOutcome {
        inventory.brewChosenIngredients()
    }

    /// Through the magic feature, which applies the effect and reports the meal back.
    func eatIngredient(_ id: FormID) {
        magic.consumeMagicItem(id)
    }

    func applyPoison(_ id: FormID) -> AlchemyActionOutcome {
        inventory.applyPoison(id)
    }
}

extension GameViewController: LockControlProviding {
    var lockSnapshot: LockControlSnapshot {
        inventory.locks.lockSnapshot
    }

    func selectLock(_ reference: FormID?) {
        inventory.locks.selectLock(reference)
    }

    func setSelectedLockLocked(_ locked: Bool) -> LockActionOutcome {
        inventoryWorld.run(inventory.locks.setSelectedLockLocked(locked))
    }

    func setPlayerCarriesEveryKey(_ enabled: Bool) {
        inventoryWorld.run(inventory.locks.setPlayerCarriesEveryKey(enabled))
    }

    func pickSelectedLock() -> LockActionOutcome {
        lockpickingMenu.openSelected()
    }
}

extension GameViewController: TrapControlProviding {
    var trapSnapshot: TrapControlSnapshot {
        trapControl.snapshot
    }

    func selectTrap(_ key: ReferenceKey?) {
        trapControl.select(key)
    }

    func fireSelectedTrap() -> TrapActionOutcome {
        trapControl.fire()
    }

    func disarmSelectedTrap() -> TrapActionOutcome {
        trapControl.disarm()
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
    func selectContainerMenuMerchant(_ reference: FormID) -> MerchantNomination {
        containerMenu.selectMerchant(reference)
    }

    @discardableResult
    func selectContainerMenuMerchantFromInteraction() -> MerchantNomination {
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
    func modifySelectedBounty(by gold: Int32, violent: Bool) -> CrimeFactionActionOutcome {
        ranCrimeCommands(crime.modifySelectedBounty(by: gold, violent: violent))
    }

    @discardableResult
    func clearSelectedBounty() -> CrimeFactionActionOutcome {
        ranCrimeCommands(crime.clearSelectedBounty())
    }

    @discardableResult
    func checkGuardConfrontation() -> CrimeFactionActionOutcome {
        ranCrimeCommands(crime.checkGuardConfrontation())
    }

    @discardableResult
    func resistArrestWithSelectedFaction() -> CrimeFactionActionOutcome {
        ranCrimeCommands(crime.resistArrestWithSelectedFaction())
    }

    @discardableResult
    func selectSocialSubjectFromCrosshair() -> CrimeFactionActionOutcome {
        crime.selectSocialSubjectFromCrosshair()
    }

    @discardableResult
    func selectPlayerAsSocialSubject() -> CrimeFactionActionOutcome {
        crime.selectPlayerAsSocialSubject()
    }

    @discardableResult
    func joinSelectedFaction(rank: Int8) -> CrimeFactionActionOutcome {
        crime.joinSelectedFaction(rank: rank)
    }

    @discardableResult
    func leaveSelectedFaction() -> CrimeFactionActionOutcome {
        crime.leaveSelectedFaction()
    }

    @discardableResult
    func barterWithSocialSubject() -> CrimeFactionActionOutcome {
        crime.barterWithSocialSubject()
    }

    private func ranCrimeCommands(_ outcome: CrimeFactionActionOutcome)
        -> CrimeFactionActionOutcome
    {
        crimeWorld.run(crime.takeCommands())
        return outcome
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

extension GameViewController: JournalControlProviding, JournalMenuHosting {}

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
    func damageSelectedActor(by amount: Float) -> ActorValueActionOutcome {
        actorValues.damageSelected(by: amount)
    }

    @discardableResult
    func restoreSelectedActor(by amount: Float) -> ActorValueActionOutcome {
        actorValues.restoreSelected(by: amount)
    }

    @discardableResult
    func setSelectedActorValue(to value: Float) -> ActorValueActionOutcome {
        actorValues.setSelectedValue(to: value)
    }

    @discardableResult
    func setSelectedActorBase(to value: Float) -> ActorValueActionOutcome {
        actorValues.setSelectedBase(to: value)
    }

    @discardableResult
    func restoreSelectedActorFully() -> ActorValueActionOutcome {
        actorValues.restoreSelectedFully()
    }

    @discardableResult
    func resetSelectedActorValues() -> ActorValueActionOutcome {
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
    func advanceSelectedSkill(byUse amount: Float) -> ProgressionActionOutcome {
        progression.advanceSelectedSkill(byUse: amount)
    }

    @discardableResult
    func incrementSelectedSkill() -> ProgressionActionOutcome {
        progression.incrementSelectedSkill()
    }

    @discardableResult
    func awardCharacterExperience(_ amount: Float) -> ProgressionActionOutcome {
        progression.awardCharacterExperience(amount)
    }

    @discardableResult
    func chooseAttributePick(_ kind: ActorValueKind) -> ProgressionActionOutcome {
        progression.chooseAttributePick(kind)
    }

    @discardableResult
    func changePerkPoints(by delta: Int) -> ProgressionActionOutcome {
        progression.changePerkPoints(by: delta)
    }

    @discardableResult
    func spendPointOnSelectedPerk() -> ProgressionActionOutcome {
        progression.spendPointOnSelectedPerk()
    }

    @discardableResult
    func makeSelectedSkillLegendary() -> ProgressionActionOutcome {
        progression.makeSelectedSkillLegendary()
    }

    @discardableResult
    func resetSelectedPerkTree() -> ProgressionActionOutcome {
        progression.resetSelectedPerkTree()
    }

    @discardableResult
    func trainWithNearestTrainer() -> ProgressionActionOutcome {
        progression.trainWithNearestTrainer()
    }

    @discardableResult
    func grantSelectedPerk() -> ProgressionActionOutcome {
        progression.grantSelectedPerk()
    }

    @discardableResult
    func revokeSelectedPerk() -> ProgressionActionOutcome {
        progression.revokeSelectedPerk()
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

    var automaticBlinkingEnabled: Bool {
        get { faceMorphs.automaticBlinkingEnabled }
        set {
            faceMorphs.automaticBlinkingEnabled = newValue
            playerSettingsStore.set(.characterBlinking, to: newValue ? 1 : 0)
        }
    }

    var dialogueExpressionsEnabled: Bool {
        get { faceMorphs.dialogueExpressionsEnabled }
        set {
            faceMorphs.dialogueExpressionsEnabled = newValue
            playerSettingsStore.set(.characterDialogueExpressions, to: newValue ? 1 : 0)
        }
    }

    var headTrackingEnabled: Bool {
        get { headTracking.isEnabled }
        set {
            headTracking.isEnabled = newValue
            playerSettingsStore.set(.characterHeadTracking, to: newValue ? 1 : 0)
        }
    }

    var headTrackingReadout: String {
        headTracking.readout(for: dialogueMenu.speakerOrTarget)
    }

    func setFaceMorphWeight(_ weight: Float, target: String) {
        faceMorphs.setFaceMorphWeight(weight, target: target)
    }

    func resetFaceMorphWeights() {
        faceMorphs.resetFaceMorphWeights()
    }
}

extension GameViewController: WorldspaceControlProviding {
    var currentWorldspace: String? {
        streamer?.worldspaceEditorID
    }

    var worldspacePlayerCell: CellSceneLocation? {
        streamer?.currentCellLocation
    }

    var worldspaceNames: [String] {
        worldData?.menuRecords?.worldspaces.keys.sorted() ?? []
    }

    func goToExterior(worldspace: String, x: Int32, y: Int32) {
        menuWorld.teleportPlayer(.grid(x: x, y: y, worldspace: worldspace), openingRaceMenu: false)
    }
}

extension GameViewController: SkyrimExportControlProviding {
    var lastSkyrimExport: SkyrimExportOutcome {
        saveGames.lastSkyrimExport
    }

    func startSkyrimExport() {
        saveGames.startSkyrimExport()
    }
}
