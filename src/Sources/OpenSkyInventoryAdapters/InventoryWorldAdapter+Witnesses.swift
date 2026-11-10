import OpenSkyAIPackages
import OpenSkyCells
public import OpenSkyConditions
import OpenSkyCrimeInterface
public import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventory
public import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
public import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorldConditions
import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

/// Witnesses that forward to the narrow parts of `InventoryWorldAdapter`.
extension InventoryWorldAdapter {
    public func questItemBases() -> Set<FormID> {
        readouts.questItemBases()
    }

    public var isPlayerSneaking: Bool {
        readouts.isPlayerSneaking
    }

    public func dropPlacement() -> DropPlacement? {
        readouts.dropPlacement()
    }

    public func nearestActorEntry() -> RuntimeReferenceEntry? {
        readouts.nearestActorEntry()
    }

    public func appearanceSkipReasons(forActor reference: FormID) -> [String] {
        readouts.appearanceSkipReasons(forActor: reference)
    }

    public func theftBounty(of item: FormID, from reference: ReferenceKey) -> Int32 {
        readouts.theftBounty(of: item, from: reference)
    }

    public func enchantmentLine(of item: FormID, on owner: ReferenceKey) -> String? {
        readouts.enchantmentLine(of: item, on: owner)
    }

    public var enchantmentCacheReadout: EnchantmentCacheReadout {
        readouts.enchantmentCacheReadout
    }

    public var gameDaysPassed: Float? {
        readouts.gameDaysPassed
    }

    public var gameMonth: Int? {
        readouts.gameMonth
    }

    public func playerSpeechSkill() -> Float? {
        readouts.playerSpeechSkill()
    }

    public func pickpocketCaughtDay(of key: ReferenceKey) -> Float? {
        pickpocket.pickpocketCaughtDay(of: key)
    }

    public func notePickpocketCatch(
        on day: Float?,
        chargedTo faction: ReferenceKey?,
        by key: ReferenceKey
    ) {
        pickpocket.notePickpocketCatch(on: day, chargedTo: faction, by: key)
    }

    public func forgetPickpocketCatch(of key: ReferenceKey) {
        pickpocket.forgetPickpocketCatch(of: key)
    }

    public func settlePickpocketCatches(chargedTo faction: ReferenceKey, forgotten: Bool) {
        pickpocket.settlePickpocketCatches(chargedTo: faction, forgotten: forgotten)
    }

    public func detectsPlayer(_ observer: ReferenceKey) -> Bool {
        pickpocket.detectsPlayer(observer)
    }

    public func applyPlacedPoison(_ poison: FormID, on target: ReferenceKey) -> Bool {
        pickpocket.applyPlacedPoison(poison, on: target)
    }

    public func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        given conditions: (subjects: PerkEvaluationSubjects, seams: ConditionContext)
    ) -> Float {
        perks.perkModified(value, at: entryPoint, on: key, given: conditions)
    }

    public func magicEffectName(_ effect: ResolvedMagicEffect) -> String {
        perks.magicEffectName(effect)
    }

    public func perkActivateLabel(for reference: FormID) -> String? {
        perks.perkActivateLabel(for: reference)
    }

    public func failingFunction(
        in conditions: ConditionList,
        sourcePlugin: String,
        temperingEnchanted: Bool?
    ) -> String? {
        recipes.failingFunction(
            in: conditions,
            sourcePlugin: sourcePlugin,
            temperingEnchanted: temperingEnchanted
        )
    }

    public func skillLevel(at index: Int32) -> Float? {
        recipes.skillLevel(at: index)
    }

    public func temperingFactor(for item: FormID) -> Float {
        recipes.temperingFactor(for: item)
    }

    public func factionMemberships(of actor: ReferenceKey) -> ActorFactionState? {
        vendor.factionMemberships(of: actor)
    }

    public func residentOwner(of key: ReferenceKey) -> InventoryOwner? {
        vendor.residentOwner(of: key)
    }

    public func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        vendor.cellLocation(of: key)
    }

    public func itemKeywords(of item: FormID) -> [FormID]? {
        vendor.itemKeywords(of: item)
    }

    public var hourOfDay: Float? {
        vendor.hourOfDay
    }

    public func vendorPlaceFacts(
        of actor: ReferenceKey,
        for place: VendorPlace
    ) -> VendorPlaceFacts? {
        vendor.vendorPlaceFacts(of: actor, for: place)
    }

    public func failingVendorCondition(
        _ conditions: ConditionList, sourcePlugin: String, merchant: ReferenceKey
    ) -> String? {
        vendor.failingVendorCondition(conditions, sourcePlugin: sourcePlugin, merchant: merchant)
    }

    public var totalGameHours: Double? {
        vendor.totalGameHours
    }

    public var vendorRestockLedger: VendorRestockLedger {
        get { vendor.vendorRestockLedger }
        set { vendor.vendorRestockLedger = newValue }
    }

    public func restockMerchantChest(_ chest: ReferenceKey) {
        vendor.restockMerchantChest(chest)
    }

    public func addItem(_ item: FormID, count: Int32, to holder: ReferenceKey) -> Bool {
        papyrus.addItem(item, count: count, to: holder)
    }

    public func removeItem(
        _ item: FormID, count: Int32, from holder: ReferenceKey, to other: ReferenceKey?
    ) -> Bool {
        papyrus.removeItem(item, count: count, from: holder, to: other)
    }

    public func unequipSlot(_ slot: Int32, on actor: ReferenceKey) -> Bool {
        papyrus.unequipSlot(slot, on: actor)
    }

    public func dropItem(_ item: FormID, count: Int32, from holder: ReferenceKey) -> ReferenceKey? {
        papyrus.dropItem(item, count: count, from: holder)
    }

    public func removeAllItems(
        from holder: ReferenceKey, to other: ReferenceKey?, removeQuestItems: Bool
    ) -> Bool {
        papyrus.removeAllItems(from: holder, to: other, removeQuestItems: removeQuestItems)
    }

    public func baselineInventory(of holder: ReferenceKey) -> ReferenceInventoryState? {
        papyrus.baselineInventory(of: holder)
    }

    public func itemCount(_ item: FormID, in holder: ReferenceKey) -> Int32? {
        papyrus.itemCount(item, in: holder)
    }

    public func equipItem(_ item: FormID, on actor: ReferenceKey) -> Bool {
        papyrus.equipItem(item, on: actor)
    }

    public func unequipItem(_ item: FormID, on actor: ReferenceKey) -> Bool {
        papyrus.unequipItem(item, on: actor)
    }

    public func setOutfit(_ outfit: FormID, on actor: ReferenceKey) -> Bool {
        papyrus.setOutfit(outfit, on: actor)
    }

    public func isEquipped(_ item: FormID, on actor: ReferenceKey) -> Bool? {
        papyrus.isEquipped(item, on: actor)
    }

    public func equippedWeapon(on actor: ReferenceKey, leftHand: Bool) -> FormID?? {
        papyrus.equippedWeapon(on: actor, leftHand: leftHand)
    }

    public func equippedShield(on actor: ReferenceKey) -> FormID?? {
        papyrus.equippedShield(on: actor)
    }

    public func unequipAll(on actor: ReferenceKey) -> Bool {
        papyrus.unequipAll(on: actor)
    }

    public func goldValue(of item: FormID) -> Int32? {
        papyrus.goldValue(of: item)
    }

    public func learnIngredientEffects(_ ingredient: FormID, indices: [Int]?) -> Bool {
        papyrus.learnIngredientEffects(ingredient, indices: indices)
    }

    public func learnNextIngredientEffect(_ ingredient: FormID) -> Int? {
        papyrus.learnNextIngredientEffect(ingredient)
    }

    public func isHostileItem(_ item: FormID) -> Bool? {
        papyrus.isHostileItem(item)
    }
}
