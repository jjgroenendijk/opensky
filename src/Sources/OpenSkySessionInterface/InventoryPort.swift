public import OpenSkyCrimeInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyWorldInterface

/// What the world adapters use of `InventoryCoordinator`.
public protocol InventoryPort: AnyObject, Sendable {
    associatedtype AlchemyLab: InventoryAlchemyLabPort
    var alchemyLab: AlchemyLab { get }
    associatedtype ArmourWeights: InventoryArmourWeightsPort
    var armourWeights: ArmourWeights { get }
    associatedtype Consumables: InventoryConsumablesPort
    var consumables: Consumables { get }
    associatedtype ContainerTrade: InventoryContainerTradePort
    var containerTrade: ContainerTrade { get }
    associatedtype CraftingBench: InventoryCraftingBenchPort
    var craftingBench: CraftingBench { get }
    associatedtype CraftingReadout: InventoryCraftingReadoutPort
    var craftingReadout: CraftingReadout { get }
    associatedtype DeathItems: InventoryDeathItemsPort
    var deathItems: DeathItems { get }
    associatedtype EquipmentChanges: InventoryEquipmentChangesPort
    var equipmentChanges: EquipmentChanges { get }
    associatedtype FavouriteItems: InventoryFavouriteItemsPort
    var favouriteItems: FavouriteItems { get }
    associatedtype FollowerTakes: InventoryFollowerTakesPort
    var followerTakes: FollowerTakes { get }
    associatedtype ItemActions: InventoryItemActionsPort
    var itemActions: ItemActions { get }
    associatedtype ItemCards: InventoryItemCardsPort
    var itemCards: ItemCards { get }
    associatedtype ItemConditions: InventoryItemConditionsPort
    var itemConditions: ItemConditions { get }
    associatedtype ItemPanels: InventoryItemPanelsPort
    var itemPanels: ItemPanels { get }
    associatedtype Pickpocketing: InventoryPickpocketingPort
    var pickpocketing: Pickpocketing { get }
    associatedtype ReadoutLines: InventoryReadoutLinesPort
    var readoutLines: ReadoutLines { get }
    associatedtype ScriptItems: InventoryScriptItemsPort
    var scriptItems: ScriptItems { get }
    associatedtype TeammateTrades: InventoryTeammateTradesPort
    var teammateTrades: TeammateTrades { get }

    associatedtype EquipmentRuntime: EquipmentRuntimePort
    associatedtype LockCoordinator: LockPort
    associatedtype VendorCoordinator: VendorPort
    associatedtype WorldItemRuntime: WorldItemRuntimePort
    var alchemySelection: [FormID]? { get }
    var equipment: EquipmentRuntime? { get }
    var locks: LockCoordinator { get }
    func name(of item: FormID) -> String
    func readout(_ stacks: [InventoryStack]) -> [ItemStackReadout]
    var runtime: WorldItemRuntime? { get }
    var vendors: VendorCoordinator? { get }

    var isCrafting: Bool { get }
}

/// The alchemy lab: ingredients, their known effects, and brewing.
public protocol InventoryAlchemyLabPort {
    var alchemyIngredients: [AlchemyIngredientReadout] { get }
    func isHostileItem(_ item: FormID) -> Bool?
    @discardableResult func learnEatenIngredient(_ item: FormID) -> AlchemyActionOutcome
    /// The HUD notices of the effects an eaten ingredient taught.
    func eatingNotices(of outcome: AlchemyActionOutcome) -> [String]
    @discardableResult func learnIngredientEffects(_ item: FormID, indices: [Int]?) -> Bool
    func learnNextIngredientEffect(_ item: FormID) -> Int?
    func registerCreatedPotions()
}

/// The weight the player carries and wears.
public protocol InventoryArmourWeightsPort {
    var playerCarriedWeight: Float { get }
    var playerWornArmourWeight: Float { get }
}

/// Using an item: eating, drinking, and applying a poison.
public protocol InventoryConsumablesPort {
    @discardableResult func applyPoison(_ poison: FormID) -> AlchemyActionOutcome
    func use(of item: FormID) -> ItemUse
    func poisonQuestion(_ poison: FormID, texts: GameSettingTexts<PoisonText>) -> String?
}

/// Moving items between holders: take all, transfer, and the holder of a container.
public protocol InventoryContainerTradePort {
    var tradeTexts: TradeTexts { get }
    func barterPricing(with merchant: ReferenceKey?) -> BarterPricing
    func containerHolder(for interaction: PlacedInteraction) -> InventoryHolder?
    func takeAll(from container: InventoryHolder) -> ItemActionOutcome
    func transfer(_ request: ContainerTransferRequest) throws -> TradeOutcome
}

/// The crafting stations: open, craft, temper, and close.
public protocol InventoryCraftingBenchPort {
    @discardableResult func closeCraftingSession() -> CraftingActionOutcome
    func labelled(_ interaction: PlacedInteraction) -> PlacedInteraction
}

/// The crafting readout and the quality names of improved items.
public protocol InventoryCraftingReadoutPort {
    var craftingSnapshot: CraftingControlSnapshot { get }
}

/// The item an actor drops on death.
public protocol InventoryDeathItemsPort {
    @discardableResult func grantDeathItem(
        to key: ReferenceKey,
        actorLevel: Int
    ) -> [InventoryStack]
}

/// Equipping and unequipping items.
public protocol InventoryEquipmentChangesPort {
    func equipItem(
        _ item: FormID?,
        on target: EquipmentTargetSelector
    ) -> InventoryResult<ItemActionOutcome>
    func unequipItem(
        _ item: FormID?,
        on target: EquipmentTargetSelector
    ) -> InventoryResult<ItemActionOutcome>
}

/// The player's favourites and hotkeys.
public protocol InventoryFavouriteItemsPort {
    func hotkeyItem(_ slot: Int) -> Result<FormID, FavouriteOutcome>
    var playerFavourites: FavouritesState { get }
    @discardableResult func toggleFavourite(_ item: FormID) -> FavouriteOutcome
}

/// Followers picking items up and taking from containers.
public protocol InventoryFollowerTakesPort {
    func followerPickUp(_ item: ReferenceKey, by follower: ReferenceKey) -> Bool
    func followerTakeAll(from key: ReferenceKey, by follower: ReferenceKey) -> InventoryResult<Bool>
}

/// Take, search, drop, and close: the item actions of the use key and the Items readout.
public protocol InventoryItemActionsPort {
    @discardableResult func dropPlayerItem(_ item: FormID?, count: Int32) -> ItemActionOutcome
    @discardableResult func dropWeapon(
        of holder: InventoryHolder,
        at placement: DropPlacement
    ) -> FormID?
    @discardableResult func take(_ interaction: PlacedInteraction) -> ItemActionOutcome
    func handleInteraction(_ action: InteractionAction) -> [InventoryCommand]
}

/// The card an item shows in the menus.
public protocol InventoryItemCardsPort {
    var menuTexts: InventoryMenuTexts { get }
    func itemCard(for item: FormID) -> InventoryItemCard?
}

/// What condition functions read from inventories.
public protocol InventoryItemConditionsPort {
    func conditionEquipment(of key: ReferenceKey) -> ActorEquipmentFacts?
    func conditionKeywordCounts(of key: ReferenceKey) -> [FormID: Int32]?
}

/// The inventory readouts: owners, equipment, and grants.
public protocol InventoryItemPanelsPort {
    func targetOwnership() -> ReferenceOwnershipReadout?
}

/// Stealing from and planting on an actor.
public protocol InventoryPickpocketingPort {
    @discardableResult func pickpocket(
        _ stack: (item: FormID, count: Int32),
        named name: String,
        from target: InventoryHolder,
        roll: Float
    ) -> PickpocketOutcome
    func pickpocketRefused(by target: ReferenceKey) -> Bool
    @discardableResult func plant(
        _ stack: (item: FormID, count: Int32),
        named name: String,
        into target: InventoryHolder,
        roll: Float
    ) -> PickpocketOutcome
}

/// The sentences the alchemy and crafting readouts show.
public protocol InventoryReadoutLinesPort {
    /// Crafts `recipe` and gives the line its outcome shows, a refusal in `texts`.
    func craftLine(_ recipe: ResolvedFormID, texts: GameSettingTexts<CraftingRefusalText>)
        -> String
    /// Toggles `item` and gives the line its outcome shows.
    func toggleAlchemyIngredientLine(_ item: FormID) -> String
    /// The line the item panel shows for `outcome`.
    func text(of outcome: ItemActionOutcome) -> String
    /// Brews the chosen ingredients and gives the line the outcome shows.
    func brewChosenIngredientsLine() -> String
}

/// The inventory calls Papyrus scripts make.
public protocol InventoryScriptItemsPort {
    func isQuestItem(_ item: FormID) -> Bool
    var questItems: Set<FormID> { get }
    func scriptAddItem(_ item: FormID, count: Int32, to key: ReferenceKey) -> Bool
    func scriptBaselineInventory(of key: ReferenceKey) -> ReferenceInventoryState?
    func scriptDropObject(
        _ item: FormID,
        count: Int32,
        from key: ReferenceKey
    ) -> InventoryResult<ReferenceKey?>
    func scriptEquipItem(_ item: FormID, on key: ReferenceKey) -> InventoryResult<Bool>
    func scriptEquippedShield(on key: ReferenceKey) -> FormID??
    func scriptEquippedWeapon(on key: ReferenceKey, leftHand: Bool) -> FormID??
    func scriptGoldValue(of item: FormID) -> Int32?
    func scriptIsEquipped(_ item: FormID, on key: ReferenceKey) -> Bool?
    func scriptItemCount(_ item: FormID, in key: ReferenceKey) -> Int32?
    func scriptRemoveAllItems(
        from key: ReferenceKey,
        to other: ReferenceKey?,
        removeQuestItems: Bool
    ) -> InventoryResult<Bool>
    func scriptRemoveItem(
        _ item: FormID,
        count: Int32,
        from key: ReferenceKey,
        to other: ReferenceKey?
    ) -> InventoryResult<Bool>
    func scriptSetOutfit(_ outfit: FormID, on key: ReferenceKey) -> InventoryResult<Bool>
    func scriptUnequipAll(on key: ReferenceKey) -> InventoryResult<Bool>
    func scriptUnequipItem(_ item: FormID, on key: ReferenceKey) -> InventoryResult<Bool>
    func scriptUnequipSlot(_ slot: Int32, on key: ReferenceKey) -> InventoryResult<Bool>
}

/// Trading with a teammate: what they carry, refuse, and wear.
public protocol InventoryTeammateTradesPort {
    func takeAllFromTeammate(_ teammate: InventoryHolder) -> ItemActionOutcome
    func teammateOutfit(of teammate: InventoryHolder) -> [FormID: Int32]
    func teammateRefusal(
        _ transfer: ContainerTransfer,
        item: FormID,
        count: Int32,
        teammate: InventoryHolder
    ) -> TeammateTradeText?
}

/// The default arguments a protocol requirement cannot carry.
extension InventoryPickpocketingPort {
    @discardableResult public func pickpocket(
        _ item: FormID,
        count: Int32 = 1,
        named name: String,
        from target: InventoryHolder,
        roll: Float
    ) -> PickpocketOutcome {
        pickpocket((item, count), named: name, from: target, roll: roll)
    }

    @discardableResult public func plant(
        _ item: FormID,
        count: Int32 = 1,
        named name: String,
        into target: InventoryHolder,
        roll: Float
    ) -> PickpocketOutcome {
        plant((item, count), named: name, into: target, roll: roll)
    }
}

extension InventoryPort {
    /// The item records the running inventory reads; nil before a world loads.
    public var itemDefinitions: ItemDefinitionStore? {
        runtime?.inventory.baselines.items
    }
}
