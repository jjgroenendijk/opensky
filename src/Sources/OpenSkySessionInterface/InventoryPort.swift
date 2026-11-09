public import OpenSkyCrimeInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyWorldInterface

/// What the world adapters use of `InventoryCoordinator`.
public protocol InventoryPort: AnyObject, Sendable {
    associatedtype EquipmentRuntime: EquipmentRuntimePort
    associatedtype LockCoordinator: LockPort
    associatedtype VendorCoordinator: VendorPort
    associatedtype WorldItemRuntime: WorldItemRuntimePort
    var alchemyIngredients: [AlchemyIngredientReadout] { get }
    var alchemySelection: [FormID]? { get }
    @discardableResult func applyPoison(_ poison: FormID) -> AlchemyActionOutcome
    func barterPricing(with merchant: ReferenceKey?) -> BarterPricing
    @discardableResult func closeCraftingSession() -> CraftingActionOutcome
    func conditionEquipment(of key: ReferenceKey) -> ActorEquipmentFacts?
    func conditionKeywordCounts(of key: ReferenceKey) -> [FormID: Int32]?
    func containerHolder(for interaction: PlacedInteraction) -> InventoryHolder?
    /// Crafts `recipe` and gives the line its outcome shows, a refusal in `texts`.
    func craftLine(_ recipe: ResolvedFormID, texts: GameSettingTexts<CraftingRefusalText>)
        -> String
    /// Toggles `item` and gives the line its outcome shows.
    func toggleAlchemyIngredientLine(_ item: FormID) -> String
    /// Brews the chosen ingredients and gives the line the outcome shows.
    func brewChosenIngredientsLine() -> String
    var craftingSnapshot: CraftingControlSnapshot { get }
    @discardableResult func dropPlayerItem(_ item: FormID?, count: Int32) -> ItemActionOutcome
    @discardableResult func dropWeapon(
        of holder: InventoryHolder,
        at placement: DropPlacement
    ) -> FormID?
    func equipItem(
        _ item: FormID?,
        on target: EquipmentTargetSelector
    ) -> InventoryResult<ItemActionOutcome>
    var equipment: EquipmentRuntime? { get }
    func followerPickUp(_ item: ReferenceKey, by follower: ReferenceKey) -> Bool
    func followerTakeAll(from key: ReferenceKey, by follower: ReferenceKey) -> InventoryResult<Bool>
    @discardableResult func grantDeathItem(
        to key: ReferenceKey,
        actorLevel: Int
    ) -> [InventoryStack]
    func hotkeyItem(_ slot: Int) -> Result<FormID, FavouriteOutcome>
    func isHostileItem(_ item: FormID) -> Bool?
    func isQuestItem(_ item: FormID) -> Bool
    func itemCard(for item: FormID) -> InventoryItemCard?
    func labelled(_ interaction: PlacedInteraction) -> PlacedInteraction
    @discardableResult func learnEatenIngredient(_ item: FormID) -> AlchemyActionOutcome
    @discardableResult func learnIngredientEffects(_ item: FormID, indices: [Int]?) -> Bool
    func learnNextIngredientEffect(_ item: FormID) -> Int?
    var locks: LockCoordinator { get }
    var menuTexts: InventoryMenuTexts { get }
    func name(of item: FormID) -> String
    @discardableResult func pickpocket(
        _ item: FormID,
        count: Int32,
        named name: String,
        from target: InventoryHolder,
        roll: Float
    ) -> PickpocketOutcome
    func pickpocketRefused(by target: ReferenceKey) -> Bool
    @discardableResult func plant(
        _ item: FormID,
        count: Int32,
        named name: String,
        into target: InventoryHolder,
        roll: Float
    ) -> PickpocketOutcome
    var playerCarriedWeight: Float { get }
    var playerFavourites: FavouritesState { get }
    var playerWornArmourWeight: Float { get }
    var questItems: Set<FormID> { get }
    func readout(_ stacks: [InventoryStack]) -> [ItemStackReadout]
    func registerCreatedPotions()
    var runtime: WorldItemRuntime? { get }
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
    @discardableResult func take(_ interaction: PlacedInteraction) -> ItemActionOutcome
    func takeAll(from container: InventoryHolder) -> ItemActionOutcome
    func takeAllFromTeammate(_ teammate: InventoryHolder) -> ItemActionOutcome
    func targetOwnership() -> ReferenceOwnershipReadout?
    func teammateOutfit(of teammate: InventoryHolder) -> [FormID: Int32]
    func teammateRefusal(
        _ transfer: ContainerTransfer,
        item: FormID,
        count: Int32,
        teammate: InventoryHolder
    ) -> TeammateTradeText?
    @discardableResult func toggleFavourite(_ item: FormID) -> FavouriteOutcome
    var tradeTexts: TradeTexts { get }
    func transfer(_ request: ContainerTransferRequest) throws -> TradeOutcome
    func unequipItem(
        _ item: FormID?,
        on target: EquipmentTargetSelector
    ) -> InventoryResult<ItemActionOutcome>
    func use(of item: FormID) -> ItemUse
    var vendors: VendorCoordinator? { get }
    func handleInteraction(_ action: InteractionAction) -> [InventoryCommand]

    var isCrafting: Bool { get }
}

/// The default arguments a protocol requirement cannot carry.
extension InventoryPort {
    public func transfer(
        _ transfer: ContainerTransfer,
        item: FormID,
        count: Int32 = 1,
        named name: String,
        container: InventoryHolder,
        vendor: Vendor?,
        merchant: ReferenceKey? = nil,
        acceptingLess: Bool = false
    ) throws -> TradeOutcome {
        var request = ContainerTransferRequest(
            transfer, item: item, name: name, container: container, vendor: vendor
        )
        request.count = count
        request.merchant = merchant
        request.acceptingLess = acceptingLess
        return try self.transfer(request)
    }
}

/// One container move, so the port requirement stays under the parameter cap.
public struct ContainerTransferRequest {
    public var transfer: ContainerTransfer
    public var item: FormID
    public var count: Int32 = 1
    public var name: String
    public var container: InventoryHolder
    public var vendor: Vendor?
    public var merchant: ReferenceKey?
    public var acceptingLess = false

    public init(
        _ transfer: ContainerTransfer, item: FormID, name: String,
        container: InventoryHolder, vendor: Vendor?
    ) {
        self.transfer = transfer
        self.item = item
        self.name = name
        self.container = container
        self.vendor = vendor
    }
}
