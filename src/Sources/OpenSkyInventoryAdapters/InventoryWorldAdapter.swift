// App side of `InventoryCoordinator` and `VendorCoordinator`: builds them from
// the provider, routes the use key, and answers `InventoryWorld` and
// `VendorWorld` from the session systems. The rules live in the coordinators
// (docs/engine/coordinators.md).

import OpenSkyAIPackages
public import OpenSkyCells
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyInventory
public import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorldConditions
public import OpenSkyWorldInterface
public import OpenSkyWorldState

/// What `InventoryWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol InventoryWorldHost: AnyObject, SendableMetatype {
    var crime: any CrimePort { get }
    var furniture: any FurniturePort { get }
    var hud: any HUDPort { get }
    var inventory: any InventoryPort { get }
    var menuScreens: any MenuScreensPort { get }
    var mapWorld: any MapWorldPort { get }
    var messages: any MessageCoordinatorPort { get }
    var streamer: any CellStreamerPort { get }
}

/// Answers `InventoryWorld` and `VendorWorld` from the session systems `game` owns.
/// Every host an `InventoryWorldAdapter` part reads, all one object.
public typealias InventoryWorldHosts =
    InventoryCommandsHost & InventoryPerksHost &
    InventoryPickpocketHost & InventoryReadoutsHost & InventoryRecipesHost & InventoryVendorHost &
    InventoryWorldHost

public final class InventoryWorldAdapter {
    public let game: any InventoryWorldHost

    let hosts: any InventoryWorldHosts

    public var readouts: InventoryReadoutsAdapter {
        InventoryReadoutsAdapter(game: hosts
        )
    }

    public var pickpocket: InventoryPickpocketAdapter {
        InventoryPickpocketAdapter(game: hosts
        )
    }

    public var perks: InventoryPerksAdapter {
        InventoryPerksAdapter(game: hosts)
    }

    public var recipes: InventoryRecipesAdapter {
        InventoryRecipesAdapter(game: hosts)
    }

    public var vendor: InventoryVendorAdapter {
        InventoryVendorAdapter(game: hosts)
    }

    public var papyrus: InventoryPapyrusAdapter {
        InventoryPapyrusAdapter(game: hosts)
    }

    public init(game: some InventoryWorldHosts) {
        hosts = game
        self.game = game
    }

    func askToServeSentence() {
        let words = game.mapWorld.settingTexts(MessageBoxText.self)
        game.messages.presentChoices(
            title: nil, text: game.crime.crimeTexts.serveSentenceQuestion,
            buttons: [words[.yes], words[.no]]
        ) { [weak self] answer in
            guard answer == 0, let self else { return }
            game.crime.serveSentence()
        }
    }

    /// Nil without inventory baselines: then there is no item runtime.
    public func sessionData(
        provider: WorldDataStores, streamer: any CellStreamerPort, store: WorldStateStore
    ) -> InventorySessionData? {
        guard let baselines = provider.inventoryBaselines else { return nil }
        let settings = provider.gameSettings
        baselines.items.enchantedValueSettings = EnchantedValueSettings.resolve(store: settings)
        var data = InventorySessionData(items: WorldItemRuntime(
            inventory: InventoryRuntime(store: store, baselines: baselines),
            references: streamer,
            crime: game.crime.reporter
        ))
        data.equipment = provider.equipmentCatalog
        data.crafting = provider.craftingCatalog
        data.rules.barterPricing = provider.barterPricing
        data.rules.cellReset = provider.cellResetSettings
        data.rules.pickpocket = PickpocketSettings.resolve(store: settings)
        data.rules.craftingSkillUse = CraftingSkillUseSettings.resolve(store: settings)
        data.texts = texts(provider: provider)
        data.alchemy.effects = provider.magicEffectStore
        data.alchemy.pluginName = provider.magicItemPluginName ?? FormIDResolver.loadOrderSpaceName
        data.alchemy.settings = AlchemySettings.resolve(store: settings)
        data.alchemy.texts = alchemyTexts
        data.locks.settings = provider.lockTrapData.lockpicking
        data.locks.lockpickItem = provider.lockTrapData.lockpickItem
        data.locks.texts = LockTexts.resolve(store: settings) { [game] in game.mapWorld.text($0) }
        return data
    }

    private func texts(provider: WorldDataStores) -> InventoryTexts {
        let settings = provider.gameSettings
        let text: GameTextResolver = { [game] in game.mapWorld.text($0) }
        var texts = InventoryTexts()
        texts.activation = game.mapWorld.settingTexts()
        texts.menu = InventoryMenuTexts.resolve(store: settings, text: text)
        texts.trade = TradeTexts.resolve(store: settings, text: text)
        texts.soul = SoulTexts.resolve(store: settings, text: text)
        texts.tempering = TemperingTexts.resolve(store: settings, text: text)
        return texts
    }

    /// A chair or a bench seats the player. A crafting station keeps its menu, and a bed
    /// its rest menu. False while the furniture switch is off.
    func useFurniture(_ interaction: PlacedInteraction) -> Bool {
        guard
            !interaction.seats.isEmpty,
            (interaction.station?.workbench.benchType ?? WorkbenchType.none) == WorkbenchType.none,
            let key = game.streamer.referenceEntry(formID: interaction.reference)?.key
        else { return false }
        if case .failure(.disabled) = game.furniture.use(key, by: .player) {
            return false
        }
        return true
    }

    /// The lab's notices, from the load order's strings.
    private var alchemyTexts: AlchemyTexts {
        let records = game.mapWorld.records
        func text(_ name: String, _ fallback: String) -> String {
            game.mapWorld.text(records?.menuTexts[name]) ?? fallback
        }
        let vanilla = AlchemyTexts.vanilla
        return AlchemyTexts(
            potionPrefix: text("sCreatedPotionNamePrefix", vanilla.potionPrefix),
            poisonPrefix: text("sCreatedPoisonNamePrefix", vanilla.poisonPrefix),
            failed: text("sPotionCreationFailed", vanilla.failed)
        )
    }

    /// A book is read where it lies, as in the game; its bar offers to take it.
    func openBook(_ interaction: PlacedInteraction) -> Bool {
        let book = game.menuScreens.book
        guard book.isBook(interaction.base), let runtime = game.inventory.runtime else {
            return false
        }
        let offer = BookTakeOffer(
            isTheft: runtime.isTheft(interaction), reference: interaction.reference
        ) { [game] in
            game.inventory.take(interaction)
        }
        return book.open(item: interaction.base, takeOffer: offer)
    }

    /// Nil without a FACT and FLST index. The memberships are read at call time.
    public static func vendorCore(provider: WorldDataStores) -> VendorCore? {
        guard
            let factionStore = provider.factionStore,
            let formLists = provider.formListStore
        else { return nil }
        return VendorCore(
            resolver: VendorResolver(factions: factionStore, formLists: formLists),
            itemPluginName: provider.magicItemPluginName
        )
    }
}

extension InventoryWorldAdapter: InventoryWorld {
    public var crosshairInteraction: PlacedInteraction? {
        game.hud.interactionTarget?.interaction
    }

    public func isBook(_ base: FormID) -> Bool {
        game.menuScreens.book.isBook(base)
    }

    public func pickpocketSkill(of key: ReferenceKey) -> Float? {
        guard let index = ActorValueIdentity.index(named: "Pickpocket") else { return nil }
        return pickpocket.actorValue(index, of: key)
    }

    public func carryWeight(of key: ReferenceKey) -> Float? {
        pickpocket.actorValue(ActorValueIdentity.carryWeightIndex, of: key)
    }
}

extension InventoryWorldAdapter {
    public var commands: InventoryCommandRunner {
        InventoryCommandRunner(game: hosts)
    }

    /// Runs the commands an inventory or lock action returned, then hands back its answer.
    @discardableResult
    public func run<Value>(_ result: InventoryResult<Value>) -> Value {
        commands.run(result)
    }

    public func run(_ commands: [InventoryCommand]) {
        self.commands.run(commands)
    }
}

extension InventoryWorldAdapter: RecipeConditionChecking {}

extension InventoryWorldAdapter: VendorWorld {}

extension InventoryWorldAdapter: PapyrusInventoryBridge {}

extension InventoryWorldAdapter: PapyrusAlchemyBridge {}

extension InventoryWorldAdapter: InventoryWorldPort {}
