public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface

extension InventoryCoordinator.ReadoutLines {
    public func craftLine(
        _ recipe: ResolvedFormID,
        texts: GameSettingTexts<CraftingRefusalText>
    ) -> String {
        coordinator.craftingBench.craft(recipe).text(texts)
    }

    public func toggleAlchemyIngredientLine(_ item: FormID) -> String {
        coordinator.alchemyLab.toggleAlchemyIngredient(item).text
    }

    public func text(of outcome: ItemActionOutcome) -> String {
        outcome.text
    }

    public func brewChosenIngredientsLine() -> String {
        let lab = coordinator.alchemyLab
        return lab.notice(of: lab.brewChosenIngredients())
    }
}
