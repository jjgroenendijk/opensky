// App side of `InventoryCoordinator` and `VendorCoordinator`: builds them from
// the provider, routes the use key, and answers `InventoryWorld` and
// `VendorWorld` from the session systems. The rules live in the coordinators
// (docs/engine/coordinators.md).

import OpenSkyActors
import OpenSkyAIPackages
public import OpenSkyCells
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyFactions
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyInventory
public import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuests
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldConditions
public import OpenSkyWorldInterface
public import OpenSkyWorldState

/// What `InventoryWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol InventoryWorldHost: AnyObject {
    var crime: any CrimePort { get }
    var furniture: any FurniturePort { get }
    var hud: any HUDPort { get }
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var menuScreens: any MenuScreensPort { get }
    var mapWorld: any MapWorldPort { get }
    var messages: any MessageCoordinatorPort { get }
    var streamer: (any CellStreamerPort)? { get }
}

/// Answers `InventoryWorld` and `VendorWorld` from the session systems `game` owns.
public final class InventoryWorldAdapter {
    public unowned let game: any InventoryWorldHost

    public let readoutsHost: any InventoryReadoutsHost
    public let pickpocketHost: any InventoryPickpocketHost
    public let perksHost: any InventoryPerksHost
    public let recipesHost: any InventoryRecipesHost
    public let vendorHost: any InventoryVendorHost
    public let papyrusHost: any InventoryPapyrusHost

    public var readouts: InventoryReadoutsAdapter {
        InventoryReadoutsAdapter(
            owner: self,
            game: readoutsHost
        )
    }

    public var pickpocket: InventoryPickpocketAdapter {
        InventoryPickpocketAdapter(
            owner: self,
            game: pickpocketHost
        )
    }

    public var perks: InventoryPerksAdapter {
        InventoryPerksAdapter(owner: self, game: perksHost)
    }

    public var recipes: InventoryRecipesAdapter {
        InventoryRecipesAdapter(owner: self, game: recipesHost)
    }

    public var vendor: InventoryVendorAdapter {
        InventoryVendorAdapter(owner: self, game: vendorHost)
    }

    public var papyrus: InventoryPapyrusAdapter {
        InventoryPapyrusAdapter(owner: self, game: papyrusHost)
    }

    public init(game: some InventoryWorldHost & InventoryReadoutsHost & InventoryPickpocketHost &
        InventoryPerksHost & InventoryRecipesHost & InventoryVendorHost & InventoryPapyrusHost)
    {
        readoutsHost = game
        pickpocketHost = game
        perksHost = game
        recipesHost = game
        vendorHost = game
        papyrusHost = game
        self.game = game
    }

    /// After the audio and Papyrus subscribers, so the activation sound plays
    /// whether or not the take succeeds. The crime reporter joins the take path.
    public func wireWorldItems(streamer: CellStreamer) {
        streamer.onInteraction.register(.worldItems) { [weak self] event in
            guard let self else { return }
            let action = event.target.interaction.action
            if action == .take, openBook(event.target.interaction) {
                return
            }
            if event.target.interaction.isBed {
                // An inmate's bed asks to serve the sentence (UESP "Skyrim:Crime").
                if game.crime.jailStay != nil {
                    askToServeSentence()
                    return
                }
                game.menuScreens.sleepWait.open(
                    sleeping: true, bed: event.target.interaction.reference
                )
                return
            }
            if useFurniture(event.target.interaction) {
                return
            }
            run(game.inventory.handleInteraction(action))
            if action == .use, game.inventory.isCrafting {
                game.menuScreens.crafting.open()
            }
        }
    }

    private func askToServeSentence() {
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
        provider: WorldDataStores, streamer: CellStreamer, store: WorldStateStore
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
    private func useFurniture(_ interaction: PlacedInteraction) -> Bool {
        guard
            !interaction.seats.isEmpty,
            (interaction.station?.workbench.benchType ?? WorkbenchType.none) == WorkbenchType.none,
            let key = game.streamer?.referenceEntry(formID: interaction.reference)?.key
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
    private func openBook(_ interaction: PlacedInteraction) -> Bool {
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
    /// Runs the commands an inventory or lock action returned, then hands back its answer.
    @discardableResult
    public func run<Value>(_ result: InventoryResult<Value>) -> Value {
        run(result.commands)
        return result.value
    }

    public func run(_ commands: [InventoryCommand]) {
        for command in commands {
            switch command {
            case let .equipmentChanged(holder):
                game.magic.equipmentChanged(on: holder)
            case .refreshInteractionTarget:
                // The streamer's raw target: the HUD's copy is already labelled, and a
                // lock label appends to the name, so labelling it twice repeats the band.
                game.hud.updateTarget(perks.labelled(game.streamer?.interactionTarget))
            case let .showNotice(text):
                game.hud.showNotification(text)
            }
        }
    }
}

extension InventoryWorldAdapter: RecipeConditionChecking {}

extension InventoryWorldAdapter: VendorWorld {}

extension InventoryWorldAdapter: PapyrusInventoryBridge {}

extension InventoryWorldAdapter: PapyrusAlchemyBridge {}

extension InventoryWorldAdapter: InventoryWorldPort {}
