// The menu a crafting station opens: its recipes, split into those the player can make
// now and the rest. At an alchemy lab it lists the carried ingredients instead, to
// choose and brew. The rules stay in the inventory feature.
// See docs/engine/crafting.md#crafting-menu.

import Foundation
public import OpenSkyFormatsESM
import OpenSkyFormatsSWF
public import OpenSkyGameData
public import OpenSkyMenusInterface

/// One recipe of the open station.
nonisolated public struct CraftingMenuRecipe: Equatable, Sendable {
    public let id: ResolvedFormID
    public let name: String
    public let canMake: Bool
    /// The title of the tab the created item goes under, such as "IRON", or nil.
    public let category: String?
    /// The tab's place in the forge's fixed tab order.
    public let categoryRank: Int

    public init(
        id: ResolvedFormID, name: String, canMake: Bool, category: String? = nil,
        categoryRank: Int = 0
    ) {
        self.id = id
        self.name = name
        self.canMake = canMake
        self.category = category
        self.categoryRank = categoryRank
    }
}

/// One carried ingredient at an alchemy lab.
nonisolated public struct CraftingMenuIngredient: Equatable, Sendable {
    public let id: FormID
    /// The name with the known effects, as the row shows it.
    public let name: String
    public let isChosen: Bool

    public init(id: FormID, name: String, isChosen: Bool) {
        self.id = id
        self.name = name
        self.isChosen = isChosen
    }
}

/// What the crafting menu needs from the app.
public protocol CraftingMenuWorld: MenuScreenWorld {
    /// The open station's name, or nil when no station is open.
    var craftingStationName: String? { get }
    var craftingStation: CraftingStationInfo? { get }
    var craftingButtonTexts: GameSettingTexts<CraftingButtonText> { get }
    var craftingTabTexts: GameSettingTexts<CraftingTabText> { get }
    var craftingRecipes: [CraftingMenuRecipe] { get }
    /// Makes one of `recipe`; the outcome text.
    func craft(_ recipe: ResolvedFormID) -> String
    func closeCraftingStation()
    /// The carried ingredients when the open station is an alchemy lab, else nil.
    var alchemyIngredients: [CraftingMenuIngredient]? { get }
    /// Chooses `ingredient`, or takes it out; the outcome text with the preview.
    func toggleIngredient(_ ingredient: FormID) -> String
    /// Brews the chosen ingredients; the outcome text.
    func brewChosenIngredients() -> String
    /// What the open arcane enchanter offers, or nil when the station is no enchanter.
    var enchanterChoices: EnchanterChoices? { get }
    var enchantingTexts: GameSettingTexts<EnchantingMenuText> { get }
    func disenchant(_ item: FormID) -> EnchanterAnswer
    /// Why `selection` cannot be made, or nil when it can.
    func enchantRefusal(_ selection: EnchanterSelection) -> String?
    func enchant(_ selection: EnchanterSelection) -> EnchanterAnswer
    /// Asks a yes or no question; `answer` gets true for yes.
    func confirm(_ text: String, answer: @escaping (Bool) -> Void)
    /// A message box with one OK button.
    func inform(_ text: String)
}

public final class CraftingMenuCoordinator: ItemListMenuScreen {
    public static let identifier: MenuIdentifier = "Crafting Menu"
    public static let hint = "W/S: row   A/D: tab   E: make or choose   R: brew   Esc: leave"

    private var recipes: [CraftingMenuRecipe] = []
    private var ingredients: [CraftingMenuIngredient] = []
    var enchanting = CraftingMenuEnchanting()
    private weak var world: (any CraftingMenuWorld)?
    /// Where the player types an enchanted item's name.
    public weak var nameEntry: TextEntryMenuCoordinator?

    public init(
        menuMode: MenuModeController,
        movies: (any MenuMovieLoading)? = nil,
        hud: (any MenuLayerOwner)? = nil,
        world: (any CraftingMenuWorld)? = nil
    ) {
        self.world = world
        super.init(
            identifier: Self.identifier,
            movie: ItemListScreenMovie(
                path: CraftingMenuMovieBridge.moviePath, title: "Crafting", hint: Self.hint
            ),
            menuMode: menuMode, layer: (movies, hud), world: world
        )
    }

    override var layout: ItemListMovieLayout {
        CraftingMenuMovieBridge.layout
    }

    /// Opens the menu on the station the world has open.
    @discardableResult
    public func open() -> Bool {
        guard !isOpen else { return false }
        guard let station = world?.craftingStationName else {
            lastResult = "Not opened: no station open"
            return false
        }
        lastResult = "Open: \(station)"
        presentList()
        return true
    }

    override func loadCategories() -> [ItemListCategory] {
        if let choices = world?.enchanterChoices, let texts = world?.enchantingTexts {
            recipes = []
            ingredients = []
            return enchanting.categories(choices, texts: texts)
        }
        if let carried = world?.alchemyIngredients {
            return ingredientCategories(carried)
        }
        ingredients = []
        let all = world?.craftingRecipes ?? []
        recipes = all
        let rows = all.enumerated().map { index, recipe in
            ItemListRow(tag: UInt32(index), name: recipe.name, isEquipped: recipe.canMake)
        }
        if
            let station = world?.craftingStation, station.improves,
            let texts = world?.craftingTabTexts
        {
            return [ItemListCategory(
                label: texts[station.improvesArmor ? .armor : .weapons],
                rows: rows
            )]
        }
        var titles: [String] = []
        for recipe in all.sorted(by: { $0.categoryRank < $1.categoryRank }) {
            if let title = recipe.category, !titles.contains(title) {
                titles.append(title)
            }
        }
        let tabs = titles.map { title in
            ItemListCategory(
                label: title,
                rows: zip(all, rows).filter { $0.0.category == title }.map(\.1)
            )
        }
        return [
            ItemListCategory(label: "Can make", rows: rows.filter(\.isEquipped)),
            ItemListCategory(label: "All", rows: rows)
        ] + tabs
    }

    /// A chosen ingredient shows as equipped, as the vanilla lab marks it.
    private func ingredientCategories(_ carried: [CraftingMenuIngredient]) -> [ItemListCategory] {
        recipes = []
        ingredients = carried
        let rows = carried.enumerated().map { index, ingredient in
            ItemListRow(tag: UInt32(index), name: ingredient.name, isEquipped: ingredient.isChosen)
        }
        return [
            ItemListCategory(
                label: (world?.craftingTabTexts ?? .vanilla)[.ingredients], rows: rows
            ),
            ItemListCategory(label: "Chosen", rows: rows.filter(\.isEquipped))
        ]
    }

    override func choose(_ row: ItemListRow, alternate: Bool) -> String {
        if let world, world.enchanterChoices != nil {
            return enchanting.choose(row, alternate: alternate, world: world) { [weak self] in
                self?.reload()
            }
        }
        if !ingredients.isEmpty || world?.alchemyIngredients != nil {
            if alternate {
                return world?.brewChosenIngredients() ?? "No game"
            }
            guard ingredients.indices.contains(Int(row.tag)) else { return "No ingredient" }
            return world?.toggleIngredient(ingredients[Int(row.tag)].id) ?? "No game"
        }
        guard let world, recipes.indices.contains(Int(row.tag)) else { return "No recipe" }
        let mode = mode
        if mode == .create, alternate {
            return "Nothing to craft"
        }
        return make(recipes[Int(row.tag)], improving: mode == .improve, world: world)
    }

    /// Asks before a recipe the player can make; a refused one shows the game's notice.
    private func make(
        _ recipe: CraftingMenuRecipe, improving: Bool, world: any CraftingMenuWorld
    ) -> String {
        guard recipe.canMake else {
            let refusal = world.craft(recipe.id)
            world.showHUDNotification(refusal)
            return refusal
        }
        let texts = world.craftingButtonTexts
        world.confirm(texts[improving ? .confirmImprove : .confirmCreate]) { [weak self] yes in
            guard yes else { return }
            self?.lastResult = world.craft(recipe.id)
            self?.reload()
        }
        return "Asked to make \(recipe.name)"
    }

    var mode: CraftingMenuMode {
        if world?.enchanterChoices != nil {
            return .enchanting
        }
        if world?.alchemyIngredients != nil {
            return .alchemy
        }
        return world?.craftingStation?.improves == true ? .improve : .create
    }

    var buttons: CraftingMenuButtons {
        let mode = mode
        var state = CraftingMenuButtons.State(mode: mode, hasRow: model.selected != nil)
        switch mode {
        case .alchemy:
            state.rowIsMarked = model.selected?.isEquipped == true
            state.chosenCount = ingredients.count { $0.isChosen }
        case .enchanting:
            state.rowIsMarked = model.selected.map(enchanting.isDestroyRow) ?? false
            state.onDisenchantTab = model.selectedCategory == 0
            state.canRename = enchanting.selection.isComplete
        case .create, .improve:
            break
        }
        return CraftingMenuButtons.make(state, texts: world?.craftingButtonTexts ?? .vanilla)
    }

    /// Alchemy clears the chosen ingredients; enchanting names the item to make.
    override func auxiliary() -> String? {
        guard let world else { return nil }
        switch mode {
        case .alchemy:
            let chosen = ingredients.filter(\.isChosen)
            guard !chosen.isEmpty else { return nil }
            for ingredient in chosen {
                _ = world.toggleIngredient(ingredient.id)
            }
            return "Cleared the chosen ingredients"
        case .enchanting:
            guard enchanting.selection.isComplete, model.selectedCategory != 0 else { return nil }
            let title = world.craftingButtonTexts[.enterItemName]
            nameEntry?.open(title: title) { [weak self] name in
                self?.enchanting.rename(name)
            }
            return "Naming the item"
        case .create, .improve:
            return nil
        }
    }

    /// The lab asks every time; the enchanter asks once something is chosen.
    override func requestClose() {
        guard let world else { return close() }
        let question: CraftingButtonText? = switch mode {
        case .alchemy: .quitAlchemy
        case .enchanting: enchanting.hasChoice ? .quitEnchanting : nil
        case .create, .improve: nil
        }
        guard let question else { return close() }
        world.confirm(world.craftingButtonTexts[question]) { [weak self] yes in
            if yes {
                self?.close()
            }
        }
    }

    override func publishMovie(_ runtime: SWFMovieRuntime) {
        super.publishMovie(runtime)
        CraftingMenuMovieBridge.publish(buttons, runtime: runtime)
    }

    override func prepareMovie(
        _ runtime: SWFMovieRuntime,
        post: @escaping @MainActor @Sendable (ItemListMovieEvent) -> Void
    ) {
        CraftingMenuMovieBridge.prepare(runtime: runtime, onEvent: post)
    }

    override func activateMovie(_ runtime: SWFMovieRuntime) {
        let station = world?.craftingStationName ?? ""
        CraftingMenuMovieBridge.activate(station: station, buttons: buttons, runtime: runtime)
    }

    override func didClose() {
        recipes = []
        ingredients = []
        enchanting = CraftingMenuEnchanting()
        world?.closeCraftingStation()
    }
}
