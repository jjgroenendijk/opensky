// Pure crafting rules: which recipes a station offers and whether the player can
// make one. Recipes are load-order wide; the inventory keys items by the raw
// FormIDs of the item plugin, so links cross through `itemPlugin`.
// See docs/engine/crafting.md.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM

/// One component the player holds too few of.
nonisolated public struct ComponentShortfall: Equatable, Sendable {
    public let item: FormID
    public let required: Int32
    public let held: Int32

    public init(item: FormID, required: Int32, held: Int32) {
        self.item = item
        self.required = required
        self.held = held
    }
}

/// Why a recipe can or cannot be made right now.
nonisolated public struct RecipeEligibility: Equatable, Sendable {
    /// The first condition function that failed. Nil when the conditions pass.
    public let failingFunction: String?
    public let shortfalls: [ComponentShortfall]
    /// A component or the created object is outside the item index.
    public let hasUnresolvedItem: Bool

    public init(
        failingFunction: String?,
        shortfalls: [ComponentShortfall],
        hasUnresolvedItem: Bool
    ) {
        self.failingFunction = failingFunction
        self.shortfalls = shortfalls
        self.hasUnresolvedItem = hasUnresolvedItem
    }

    public var isEligible: Bool {
        failingFunction == nil && shortfalls.isEmpty && !hasUnresolvedItem
    }

    /// Whether the crafting menu lists the recipe. The conditions are its
    /// pre-requisites to appear; missing components only mark the row.
    public var isOffered: Bool {
        failingFunction == nil
    }
}

/// One recipe in item-plugin terms. A nil item is a link outside the item index.
nonisolated public struct CraftingRecipe: Equatable, Sendable {
    public struct Component: Equatable, Sendable {
        public let item: FormID?
        public var count: Int32
        /// The items of a `FLST` component, any of which counts toward it
        /// (`docs/formats/recipes.md`). Empty for a plain item.
        public var choices: [FormID]

        public init(item: FormID?, count: Int32, choices: [FormID] = []) {
            self.item = item
            self.count = count
            self.choices = choices
        }
    }

    public let id: ResolvedFormID
    public let editorID: String?
    public let sourcePlugin: String
    public let conditions: ConditionList
    public let created: FormID?
    public let createdCount: Int32
    public let components: [Component]

    public init(
        id: ResolvedFormID,
        editorID: String?,
        sourcePlugin: String,
        conditions: ConditionList,
        created: FormID?,
        createdCount: Int32,
        components: [Component]
    ) {
        self.id = id
        self.editorID = editorID
        self.sourcePlugin = sourcePlugin
        self.conditions = conditions
        self.created = created
        self.createdCount = createdCount
        self.components = components
    }
}

/// What the use key found: a station, its recipe keywords, and the skill it trains.
nonisolated public struct CraftingStationInfo: Equatable, Sendable {
    /// The station's keywords that some recipe names, in `KWDA` order.
    public let keywords: [ResolvedFormID]
    /// Actor-value index of the `WBDT` skill. Nil when the bench trains none.
    public let skill: Int32?
    /// A grindstone or armor table: its recipes improve a held item.
    public let improves: Bool
    /// An alchemy lab: it brews from ingredients, with no recipe.
    public let brews: Bool
    /// An armor table, which improves armour; a grindstone improves weapons.
    public let improvesArmor: Bool
    /// An arcane enchanter: it disenchants and enchants, with no recipe.
    public var enchants = false

    public init(
        keywords: [ResolvedFormID], skill: Int32?, improves: Bool = false, brews: Bool = false,
        improvesArmor: Bool = false
    ) {
        self.keywords = keywords
        self.skill = skill
        self.improves = improves
        self.brews = brews
        self.improvesArmor = improvesArmor
    }
}

/// A FURN base with `WBDT` in the item plugin, for opening a session without walking there.
nonisolated public struct CraftingStationChoice: Equatable, Sendable {
    let base: FormID
    let editorID: String
    public let workbench: Workbench
    public let keywords: [FormID]
}

nonisolated public struct CraftingCatalog: Sendable {
    public let recipes: RecipeStore
    /// The plugin the station keywords and the inventory's item FormIDs belong to.
    public let itemPlugin: FormIDResolver
    /// Every workbench base in the item plugin that offers a recipe, by editor ID.
    public let stations: [CraftingStationChoice]
    /// The form lists a component may name. Nil treats every component as one item.
    public let formLists: FormListStore?
    /// The tab each created item goes under.
    public var categories: CraftingCategories = .empty

    public init(
        recipes: RecipeStore,
        itemPlugin: FormIDResolver,
        stations: [CraftingStationChoice],
        formLists: FormListStore? = nil
    ) {
        self.recipes = recipes
        self.itemPlugin = itemPlugin
        self.stations = stations
        self.formLists = formLists
    }

    init(
        recipes: RecipeStore, itemPlugin: FormIDResolver, file: ESMFile,
        formLists: FormListStore? = nil
    ) {
        self.init(
            recipes: recipes, itemPlugin: itemPlugin, loadOrder: LoadOrderPlugins(file: file),
            formLists: formLists
        )
    }

    /// Builds the catalog with every recipe-offering FURN base and every alchemy lab.
    /// `itemPlugin` must be the space `loadOrder` reads in.
    public init(
        recipes: RecipeStore, itemPlugin: FormIDResolver, loadOrder: LoadOrderPlugins,
        formLists: FormListStore? = nil
    ) {
        let probe = CraftingCatalog(recipes: recipes, itemPlugin: itemPlugin, stations: [])
        let offering = Self.stations(in: loadOrder).filter {
            let station = probe.station(workbench: $0.workbench, keywords: $0.keywords)
            return station.brews || station.enchants || !station.keywords.isEmpty
        }
        self.init(
            recipes: recipes, itemPlugin: itemPlugin, stations: offering, formLists: formLists
        )
        categories = CraftingCategories(loadOrder: loadOrder, itemPlugin: itemPlugin)
    }

    /// The station query. A bench whose keywords name no recipe gets empty `keywords`.
    public func station(workbench: Workbench, keywords: [FormID]) -> CraftingStationInfo {
        var station = CraftingStationInfo(
            keywords: keywords.compactMap(itemPlugin.resolve).filter {
                !recipes.recipes(workbenchKeyword: $0).isEmpty
            },
            skill: workbench.skillName.flatMap(ActorValueIdentity.index(named:)),
            improves: [.smithingWeapon, .smithingArmor].contains(workbench.benchType),
            brews: [.alchemy, .alchemyExperiment].contains(workbench.benchType),
            improvesArmor: workbench.benchType == .smithingArmor
        )
        station.enchants = [.enchanting, .enchantingExperiment].contains(workbench.benchType)
        return station
    }

    private static func stations(in loadOrder: LoadOrderPlugins) -> [CraftingStationChoice] {
        var skipped = SkippedRecords()
        let bases = loadOrder
            .indexRecords(of: "FURN", skipped: &skipped) { try ModelBase(record: $0) }
        return bases.compactMap { raw, base in
            guard let workbench = base.workbench, let editorID = base.editorID else { return nil }
            return CraftingStationChoice(
                base: FormID(stored: raw),
                editorID: editorID,
                workbench: workbench,
                keywords: base.keywords.keywords
            )
        }
        .sorted { $0.editorID < $1.editorID }
    }

    /// Every recipe the station offers, in keyword then load order.
    public func recipes(at station: CraftingStationInfo) -> [CraftingRecipe] {
        station.keywords.flatMap { recipes.recipes(workbenchKeyword: $0) }.map(recipe)
    }

    public func recipe(_ resolved: ResolvedRecipe) -> CraftingRecipe {
        CraftingRecipe(
            id: resolved.id,
            editorID: resolved.recipe.editorID,
            sourcePlugin: resolved.sourcePlugin,
            conditions: resolved.recipe.conditions,
            created: resolved.createdObject.flatMap(itemPlugin.localFormID),
            createdCount: Int32(resolved.recipe.effectiveCreatedCount),
            components: resolved.components.map {
                CraftingRecipe.Component(
                    item: $0.item.flatMap(itemPlugin.localFormID),
                    count: $0.count,
                    choices: $0.item.map(choices(of:)) ?? []
                )
            }
        )
    }

    /// This catalog, reading form-list components through `formLists`.
    public func with(formLists: FormListStore) -> CraftingCatalog {
        var catalog = CraftingCatalog(
            recipes: recipes, itemPlugin: itemPlugin, stations: stations, formLists: formLists
        )
        catalog.categories = categories
        return catalog
    }

    /// The leaf items of `id` when it is a form list, in list order.
    private func choices(of id: ResolvedFormID) -> [FormID] {
        guard let flattened = formLists?.flattened(id) else { return [] }
        return flattened.entries.compactMap { $0.flatMap(itemPlugin.localFormID) }
    }

    /// The verdict for `recipe`, given held counts and the condition answer.
    public static func eligibility(
        of recipe: CraftingRecipe,
        held: (FormID) -> Int32,
        isKnownItem: (FormID) -> Bool,
        failingFunction: String?
    ) -> RecipeEligibility {
        var unresolved = recipe.created.map { !isKnownItem($0) } ?? true
        var shortfalls: [ComponentShortfall] = []
        for component in required(recipe) {
            guard let item = component.item else {
                unresolved = true
                continue
            }
            let count = component.choices.isEmpty
                ? held(item)
                : Int32(clamping: component.choices.reduce(Int64(0)) { $0 + Int64(held($1)) })
            if count < component.count {
                shortfalls.append(
                    ComponentShortfall(item: item, required: component.count, held: count)
                )
            }
        }
        return RecipeEligibility(
            failingFunction: failingFunction,
            shortfalls: shortfalls,
            hasUnresolvedItem: unresolved
        )
    }

    /// Components merged by item, positive counts only, in first-seen order.
    public static func required(_ recipe: CraftingRecipe) -> [CraftingRecipe.Component] {
        var merged: [CraftingRecipe.Component] = []
        for component in recipe.components where component.count >= 1 {
            if
                let item = component.item,
                let index = merged.firstIndex(where: { $0.item == item })
            {
                merged[index].count = Int32(
                    clamping: Int64(merged[index].count) + Int64(component.count)
                )
            } else {
                merged.append(component)
            }
        }
        return merged
    }
}
