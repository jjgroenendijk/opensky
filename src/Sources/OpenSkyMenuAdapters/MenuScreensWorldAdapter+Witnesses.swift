import Foundation
import OpenSkyCamera
import OpenSkyCells
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface

extension MenuScreensWorldAdapter: BookMenuWorld {}
extension MenuScreensWorldAdapter: CraftingMenuWorld {}
extension MenuScreensWorldAdapter: TutorialMenuWorld {}
extension MenuScreensWorldAdapter: MapMovieWorld {}
extension MenuScreensWorldAdapter: TrainingMenuWorld {}
extension MenuScreensWorldAdapter: MagicMenuWorld {}
extension MenuScreensWorldAdapter: GiftMenuWorld {}

/// Witnesses that forward to the narrow parts of `MenuScreensWorldAdapter`.
extension MenuScreensWorldAdapter {
    public func bookContent(_ item: FormID) -> BookContent? {
        craftingDesk.bookContent(item)
    }

    public func readBook(_ item: FormID) -> String? {
        craftingDesk.readBook(item)
    }

    public func noteBookRead(_ item: FormID, reference: FormID?) {
        craftingDesk.noteBookRead(item, reference: reference)
    }

    public var carriedBooks: [FormID] {
        craftingDesk.carriedBooks
    }

    public var craftingStationName: String? {
        craftingDesk.craftingStationName
    }

    public var craftingStation: CraftingStationInfo? {
        craftingDesk.craftingStation
    }

    public var craftingButtonTexts: GameSettingTexts<CraftingButtonText> {
        craftingDesk.craftingButtonTexts
    }

    public var craftingRecipes: [CraftingMenuRecipe] {
        craftingDesk.craftingRecipes
    }

    public func craft(_ recipe: ResolvedFormID) -> String {
        craftingDesk.craft(recipe)
    }

    public func closeCraftingStation() {
        craftingDesk.closeCraftingStation()
    }

    public var alchemyIngredients: [CraftingMenuIngredient]? {
        craftingDesk.alchemyIngredients
    }

    public func toggleIngredient(_ ingredient: FormID) -> String {
        craftingDesk.toggleIngredient(ingredient)
    }

    public func brewChosenIngredients() -> String {
        craftingDesk.brewChosenIngredients()
    }

    public var enchanterChoices: EnchanterChoices? {
        craftingDesk.enchanterChoices
    }

    public var enchantingTexts: GameSettingTexts<EnchantingMenuText> {
        craftingDesk.enchantingTexts
    }

    public func disenchant(_ item: FormID) -> EnchanterAnswer {
        craftingDesk.disenchant(item)
    }

    public func enchantRefusal(_ selection: EnchanterSelection) -> String? {
        craftingDesk.enchantRefusal(selection)
    }

    public func enchant(_ selection: EnchanterSelection) -> EnchanterAnswer {
        craftingDesk.enchant(selection)
    }

    public func confirm(_ text: String, answer: @escaping (Bool) -> Void) {
        craftingDesk.confirm(text, answer: answer)
    }

    public func inform(_ text: String) {
        craftingDesk.inform(text)
    }

    public func helpTopic(_ editorID: String) -> HelpTopic? {
        guides.helpTopic(editorID)
    }

    public var helpTopicEditorIDs: [String] {
        guides.helpTopicEditorIDs
    }

    public func buttonName(forUserEvent event: String) -> String? {
        guides.buttonName(forUserEvent: event)
    }

    public func mapScreenPoint(_ point: SIMD3<Float>) -> SIMD2<Float>? {
        guides.mapScreenPoint(point)
    }

    public var nearestTrainer: ReferenceKey? {
        guides.nearestTrainer
    }

    public func trainingCard(trainer: ReferenceKey) -> TrainingCard? {
        guides.trainingCard(trainer: trainer)
    }

    public func train(with trainer: ReferenceKey) -> String? {
        guides.train(with: trainer)
    }

    public var magicMenuCategories: [ItemListCategory] {
        giftLists.magicMenuCategories
    }

    public func readySpell(at index: Int, leftHand: Bool) -> String {
        giftLists.readySpell(at: index, leftHand: leftHand)
    }

    public func shoutUnlockStep(at index: Int) -> ShoutUnlockStep? {
        giftLists.shoutUnlockStep(at: index)
    }

    public func unlockShout(at index: Int) -> String {
        giftLists.unlockShout(at: index)
    }

    public var nearestActor: ReferenceKey? {
        giftLists.nearestActor
    }

    public func giftCategories(
        actor: ReferenceKey,
        request: GiftMenuRequest
    ) -> [ItemListCategory] {
        giftLists.giftCategories(actor: actor, request: request)
    }

    public func give(_ item: FormID, actor: ReferenceKey, giving: Bool) -> String {
        giftLists.give(item, actor: actor, giving: giving)
    }

    public func giftRefusal(_ item: FormID, actor: ReferenceKey, giving: Bool) -> String? {
        giftLists.giftRefusal(item, actor: actor, giving: giving)
    }
}
