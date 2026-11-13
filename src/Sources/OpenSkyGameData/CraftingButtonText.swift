// The crafting menu's button labels and its yes-or-no questions, from their string
// settings. See docs/engine/crafting.md#buttons-and-questions.

nonisolated public enum CraftingButtonText: String, GameSettingTextKey {
    case select = "sSelect"
    case exit = "sExit"
    case craft = "sCraft"
    case create = "sCreate"
    case add = "sAdd"
    case remove = "sRemove"
    case clearSelections = "sClearSelections"
    case learn = "sLearn"
    case renameItem = "sRenameItem"
    case enterItemName = "sEnterItemName"
    case confirmCreate = "sConstructibleMenuConfirm"
    case confirmImprove = "sSmithingConfirm"
    case quitAlchemy = "sQuitAlchemy"
    case quitEnchanting = "sQuitEnchanting"

    public var fallback: String {
        switch self {
        case .select: "Select"
        case .exit: "Exit"
        case .craft: "Craft"
        case .create: "Create"
        case .add: "Add"
        case .remove: "Remove"
        case .clearSelections: "Clear Selections"
        case .learn: "Learn"
        case .renameItem: "Rename Item"
        case .enterItemName: "Enter Item Name"
        case .confirmCreate: "Do you want to create this item?"
        case .confirmImprove: "Do you want to improve this item?"
        case .quitAlchemy: "Quit alchemy?"
        case .quitEnchanting: "Quit enchanting?"
        }
    }
}
