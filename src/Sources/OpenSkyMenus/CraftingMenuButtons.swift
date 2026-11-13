// The crafting menu's four bottom-bar buttons. The movie keeps them in
// `/Menu.ButtonText` (select, exit, aux, craft) and blanks the craft button while
// `bCanCraft` is false. See docs/engine/crafting.md#buttons-and-questions.

import OpenSkyGameData

/// What the open station does, which picks the labels and the questions.
nonisolated enum CraftingMenuMode: Equatable {
    case create, improve, alchemy, enchanting
}

/// The labels the movie shows; an empty label hides its button.
nonisolated struct CraftingMenuButtons: Equatable {
    var select: String
    var exit: String
    var aux = ""
    var craft: String
    var canCraft: Bool

    var labels: [String] {
        [select, exit, aux, craft]
    }

    /// What the menu shows now: the mode, and the state the labels follow.
    struct State {
        var mode: CraftingMenuMode
        var hasRow: Bool
        /// Alchemy: the highlighted ingredient is chosen; enchanting: it is a disenchant row.
        var rowIsMarked = false
        var chosenCount = 0
        var onDisenchantTab = false
        var canRename = false
    }

    /// The game's labels for each station. The alchemy craft button waits for two
    /// chosen ingredients, OpenSky's reading of "a valid potion".
    static func make(_ state: State, texts: GameSettingTexts<CraftingButtonText>) -> Self {
        var buttons = Self(
            select: texts[.select], exit: texts[.exit], craft: texts[.craft], canCraft: true
        )
        switch state.mode {
        case .create:
            buttons.select = texts[.create]
            buttons.canCraft = false
        case .improve:
            buttons.canCraft = state.hasRow
        case .alchemy:
            buttons.select = texts[state.rowIsMarked ? .remove : .add]
            buttons.aux = state.chosenCount > 0 ? texts[.clearSelections] : ""
            buttons.canCraft = state.chosenCount >= 2
        case .enchanting:
            buttons.select = texts[state.rowIsMarked ? .learn : .select]
            buttons.aux = state.canRename && !state.onDisenchantTab ? texts[.renameItem] : ""
            buttons.craft = state.onDisenchantTab ? "" : texts[.craft]
        }
        return buttons
    }
}
