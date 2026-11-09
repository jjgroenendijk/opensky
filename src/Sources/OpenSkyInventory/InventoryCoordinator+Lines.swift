public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface

extension InventoryCoordinator {
    public func craftLine(
        _ recipe: ResolvedFormID,
        texts: GameSettingTexts<CraftingRefusalText>
    ) -> String {
        craft(recipe).text(texts)
    }

    public func toggleAlchemyIngredientLine(_ item: FormID) -> String {
        toggleAlchemyIngredient(item).text
    }

    public func brewChosenIngredientsLine() -> String {
        brewChosenIngredients().text
    }
}
