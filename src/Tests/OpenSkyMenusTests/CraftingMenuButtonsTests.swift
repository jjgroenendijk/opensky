import OpenSkyGameData
@testable import OpenSkyMenus
import Testing

struct CraftingMenuButtonsTests {
    private let texts = GameSettingTexts<CraftingButtonText>.vanilla

    @Test func aForgeCreatesAndNeverShowsCraft() {
        let buttons = CraftingMenuButtons.make(.init(mode: .create, hasRow: true), texts: texts)
        #expect(buttons.labels == ["Create", "Exit", "", "Craft"])
        #expect(!buttons.canCraft)
    }

    @Test func aBenchCraftsOnlyWithARow() {
        #expect(CraftingMenuButtons.make(.init(mode: .improve, hasRow: true), texts: texts)
            .canCraft)
        #expect(!CraftingMenuButtons.make(.init(mode: .improve, hasRow: false), texts: texts)
            .canCraft)
    }

    @Test func theLabAddsRemovesAndClears() {
        var state = CraftingMenuButtons.State(mode: .alchemy, hasRow: true)
        #expect(CraftingMenuButtons.make(state, texts: texts).labels == [
            "Add",
            "Exit",
            "",
            "Craft"
        ])
        state.rowIsMarked = true
        state.chosenCount = 2
        let buttons = CraftingMenuButtons.make(state, texts: texts)
        #expect(buttons.labels == ["Remove", "Exit", "Clear Selections", "Craft"])
        #expect(buttons.canCraft)
    }

    @Test func theEnchanterLearnsOnItsFirstTabAndRenamesElsewhere() {
        var state = CraftingMenuButtons.State(mode: .enchanting, hasRow: true)
        state.rowIsMarked = true
        state.onDisenchantTab = true
        state.canRename = true
        #expect(CraftingMenuButtons.make(state, texts: texts).labels == ["Learn", "Exit", "", ""])
        state.rowIsMarked = false
        state.onDisenchantTab = false
        #expect(
            CraftingMenuButtons.make(state, texts: texts).labels
                == ["Select", "Exit", "Rename Item", "Craft"]
        )
    }
}
