// App side of `InventoryCoordinator` and `VendorCoordinator`: builds them from
// the provider, routes the use key, and answers `InventoryWorld` and
// `VendorWorld` from the session systems. The rules live in the coordinators
// (docs/engine/coordinators.md).

import OpenSkyActors
import OpenSkyCells
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyFactions
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `InventoryWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol InventoryWorldHost: AnyObject {
    var actorValues: ActorValueCoordinator { get }
    var actorWorld: ActorWorldAdapter { get }
    var crime: CrimeCoordinator { get }
    var factions: FactionCoordinator { get }
    var hud: HUDCoordinator { get }
    var inventory: InventoryCoordinator { get }
    var magic: MagicCoordinator { get }
    var menuScreens: MenuScreens { get }
    var mapWorld: MapWorldAdapter { get }
    var perception: PerceptionCoordinator { get }
    var perkActivation: PerkActivationCoordinator { get }
    var perks: PerkCoordinator { get }
    var player: PlayerCoordinator { get }
    var progression: ProgressionCoordinator { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var runtimeState: RuntimeStateCoordinator { get }
    var scripts: ScriptCoordinator { get }
    var streamer: CellStreamer? { get }
    var worldState: WorldStateStore { get }
    var worldData: WorldDataStores? { get }
}

/// Answers `InventoryWorld` and `VendorWorld` from the session systems `game` owns.
final class InventoryWorldAdapter {
    unowned let game: any InventoryWorldHost

    init(game: any InventoryWorldHost) {
        self.game = game
    }

    /// After the audio and Papyrus subscribers, so the activation sound plays
    /// whether or not the take succeeds.
    func wireWorldItems(provider: WorldDataStores, streamer: CellStreamer) {
        guard let baselines = provider.inventoryBaselines
        else { return }
        baselines.items.enchantedValueSettings = EnchantedValueSettings
            .resolve(store: provider.gameSettings)
        let coordinator = game.inventory
        coordinator.activationTexts = game.mapWorld.settingTexts()
        coordinator.wire(
            inventory: InventoryRuntime(store: game.worldState, baselines: baselines),
            references: streamer,
            catalog: provider.equipmentCatalog,
            pricing: provider.barterPricing,
            cellReset: provider.cellResetSettings
        )
        game.scripts.bridge?.inventory = self
        game.scripts.bridge?.alchemy = self
        coordinator.wireCrafting(
            catalog: provider.craftingCatalog, conditions: self, skills: game.progression
        )
        coordinator.craftingSkillUse = CraftingSkillUseSettings
            .resolve(store: provider.gameSettings)
        coordinator.menuTexts = InventoryMenuTexts
            .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        coordinator.tradeTexts = TradeTexts
            .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        coordinator.pickpocketSettings = PickpocketSettings.resolve(store: provider.gameSettings)
        coordinator.soulTexts = SoulTexts
            .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        coordinator.temperingTexts = TemperingTexts
            .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        coordinator.wireAlchemy(
            effects: provider.magicEffectStore,
            pluginName: provider.magicItemPluginName ?? FormIDResolver.loadOrderSpaceName,
            settings: AlchemySettings.resolve(store: provider.gameSettings),
            texts: alchemyTexts
        )
        streamer.onInteraction.add { [weak self] event in
            guard let self else { return }
            let action = event.target.interaction.action
            if action == .take, openBook(event.target.interaction) {
                return
            }
            if event.target.interaction.isBed {
                // An inmate's bed serves the sentence (UESP "Skyrim:Crime").
                if game.crime.serveSentence() {
                    return
                }
                game.menuScreens.sleepWait.open(
                    sleeping: true, bed: event.target.interaction.reference
                )
                return
            }
            run(game.inventory.handleInteraction(action))
            if action == .use, game.inventory.crafting != nil {
                game.menuScreens.crafting.open()
            }
        }
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

    /// After `wireFactions`, whose runtime answers the memberships.
    func wireVendors(provider: WorldDataStores) {
        guard
            let factionStore = provider.factionStore,
            let formLists = provider.formListStore
        else { return }
        let core = VendorCore(
            resolver: VendorResolver(factions: factionStore, formLists: formLists),
            itemPluginName: provider.magicItemPluginName
        )
        let vendors = VendorCoordinator(core: core, world: self)
        vendors.restockSettings = VendorRestockSettings.resolve(store: provider.gameSettings)
        game.inventory.vendors = vendors
    }
}

extension InventoryWorldAdapter: InventoryWorld {
    var crosshairInteraction: PlacedInteraction? {
        game.hud.interactionTarget?.interaction
    }

    func isBook(_ base: FormID) -> Bool {
        game.menuScreens.book.isBook(base)
    }

    var isPlayerSneaking: Bool {
        game.player.isSneaking
    }

    func dropPlacement() -> DropPlacement? {
        guard let gameSession = game.gameSession, let location = game.streamer?.currentCellLocation
        else { return nil }
        return WorldItemRuntime.dropPlacement(
            in: location,
            eye: gameSession.freeFlyCamera.position,
            forward: gameSession.freeFlyCamera.forward
        )
    }

    func nearestActorEntry() -> RuntimeReferenceEntry? {
        guard let gameSession = game.gameSession else { return nil }
        return game.streamer?.nearestActorEntry(to: gameSession.freeFlyCamera.position)
    }

    func containerInteractions() -> [PlacedInteraction] {
        game.streamer?.containerInteractions() ?? []
    }

    func appearanceSkipReasons(forActor reference: FormID) -> [String] {
        game.streamer?.appearanceSkipReasons(forActor: reference) ?? []
    }

    func theftBounty(of item: FormID, from reference: ReferenceKey) -> Int32 {
        game.crime.theftBounty(of: item, from: reference)
    }

    func enchantmentLine(of item: FormID, on owner: ReferenceKey) -> String? {
        game.magic.enchantmentLine(of: item, on: game.actorWorld.actorValueHolder(for: owner))
    }

    var enchantmentCacheReadout: EnchantmentCacheReadout {
        game.magic.enchantmentCacheReadout
    }

    var gameDaysPassed: Float? {
        game.gameSession?.gameClock.daysPassed
    }

    var gameMonth: Int? {
        game.gameSession?.gameClock.month
    }

    func playerSpeechSkill() -> Float? {
        guard let speech = ActorValueIdentity.index(named: "Speechcraft") else { return nil }
        return game.actorValues.runtime?.value(at: speech, on: .player)
    }

    func pickpocketSkill(of key: ReferenceKey) -> Float? {
        guard
            let index = ActorValueIdentity.index(named: "Pickpocket"),
            let runtime = game.actorValues.runtime,
            let holder = key == .player ? .player : game.actorWorld.actorValueHolder(for: key)
        else { return nil }
        return runtime.value(at: index, on: holder)
    }

    func detectsPlayer(_ observer: ReferenceKey) -> Bool {
        game.perception.runtime?.state(observer: observer, target: .player).state == .detected
    }

    func applyPlacedPoison(_ poison: FormID, on target: ReferenceKey) -> Bool {
        game.magic.applyPlacedPoison(poison, by: .player, on: target) != nil
    }

    var playerCarryCapacity: Float? {
        game.actorValues.runtime?.value(at: ActorValueIdentity.carryWeightIndex, on: .player)
    }

    func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> Float {
        game.perks.modified(
            value,
            at: entryPoint,
            on: key,
            subjects: { _ in subjects },
            seams: seams
        )
    }

    func magicEffectName(_ effect: ResolvedMagicEffect) -> String {
        game.mapWorld.text(effect.effect.name) ?? effect.displayName
    }

    func perkActivateLabel(for reference: FormID) -> String? {
        guard let key = game.streamer?.referenceEntry(formID: reference)?.key else { return nil }
        if let label = game.perkActivation.promptLabel(on: key) {
            return label
        }
        let choice = game.perks.choices(
            at: .setActivateLabel,
            on: .player,
            subjects: { _ in PerkEvaluationSubjects(owner: .player, target: key) },
            seams: ConditionContext()
        ).first
        if case let .localizedText(text)? = choice?.text {
            return game.mapWorld.text(text)
        }
        return choice?.inlineText
    }

    /// The streamer's target with the runtime label, such as a harvested plant's.
    func labelled(_ target: InteractionTarget?) -> InteractionTarget? {
        target.map {
            InteractionTarget(
                interaction: game.inventory.labelled($0.interaction),
                hitPosition: $0.hitPosition,
                distance: $0.distance
            )
        }
    }
}

extension InventoryWorldAdapter {
    /// Runs the commands an inventory or lock action returned, then hands back its answer.
    @discardableResult
    func run<Value>(_ result: InventoryResult<Value>) -> Value {
        run(result.commands)
        return result.value
    }

    func run(_ commands: [InventoryCommand]) {
        for command in commands {
            switch command {
            case let .equipmentChanged(holder):
                game.magic.equipmentChanged(on: holder)
            case .refreshInteractionTarget:
                // The streamer's raw target: the HUD's copy is already labelled, and a
                // lock label appends to the name, so labelling it twice repeats the band.
                game.hud.updateTarget(labelled(game.streamer?.interactionTarget))
            case let .showNotice(text):
                game.hud.showNotification(text)
            }
        }
    }
}

extension InventoryWorldAdapter: RecipeConditionChecking {
    /// Recipes run on the player, who also answers `GetItemCount`.
    func failingFunction(
        in conditions: ConditionList,
        sourcePlugin _: String,
        temperingEnchanted: Bool?
    ) -> String? {
        var context = game.runtimeState.conditionContext()
        context.subject = .player
        context.tempering = TemperingConditionResolution(isEnchanted: temperingEnchanted)
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.firstFailure(in: conditions.conditions).map(evaluator.functionName(of:))
    }

    func skillLevel(at index: Int32) -> Float? {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: .player)
        else { return nil }
        return runtime.value(at: index, on: holder)
    }

    func temperingFactor(for item: FormID) -> Float {
        let subject = game.inventory.runtime?.inventory.baselines.items.conditionSubject(of: item)
        return perkModified(
            1,
            at: .modTemperingHealth,
            on: .player,
            subjects: PerkEvaluationSubjects(owner: .player).binding(.item, to: subject),
            seams: ConditionContext()
        )
    }
}

extension InventoryWorldAdapter: VendorWorld {
    func factionMemberships(of actor: ReferenceKey) -> ActorFactionState? {
        game.factions.memberships(of: actor)
    }

    func residentOwner(of key: ReferenceKey) -> InventoryOwner? {
        guard let entry = game.streamer?.referenceEntry(key: key) else { return nil }
        if let actor = entry.placedActor {
            return .actor(base: actor.base)
        }
        return entry.placedReference.map { .container(base: $0.base) }
    }

    func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        game.streamer?.cellLocation(of: key)
    }

    func itemKeywords(of item: FormID) -> [FormID]? {
        game.inventory.runtime?.inventory.baselines.items.definition(item)?.keywords
    }

    var hourOfDay: Float? {
        game.gameSession?.gameClock.hourOfDay
    }
}

extension InventoryWorldAdapter: PapyrusInventoryBridge {
    func addItem(_ item: FormID, count: Int32, to holder: ReferenceKey) -> Bool {
        game.inventory.scriptAddItem(item, count: count, to: holder)
    }

    func removeItem(
        _ item: FormID, count: Int32, from holder: ReferenceKey, to other: ReferenceKey?
    ) -> Bool {
        run(game.inventory.scriptRemoveItem(item, count: count, from: holder, to: other))
    }

    func unequipSlot(_ slot: Int32, on actor: ReferenceKey) -> Bool {
        run(game.inventory.scriptUnequipSlot(slot, on: actor))
    }

    func dropItem(_ item: FormID, count: Int32, from holder: ReferenceKey) -> ReferenceKey? {
        run(game.inventory.scriptDropObject(item, count: count, from: holder))
    }

    func removeAllItems(from holder: ReferenceKey, to other: ReferenceKey?) -> Bool {
        run(game.inventory.scriptRemoveAllItems(from: holder, to: other))
    }

    func baselineInventory(of holder: ReferenceKey) -> ReferenceInventoryState? {
        game.inventory.scriptBaselineInventory(of: holder)
    }

    func itemCount(_ item: FormID, in holder: ReferenceKey) -> Int32? {
        game.inventory.scriptItemCount(item, in: holder)
    }

    func equipItem(_ item: FormID, on actor: ReferenceKey) -> Bool {
        run(game.inventory.scriptEquipItem(item, on: actor))
    }

    func unequipItem(_ item: FormID, on actor: ReferenceKey) -> Bool {
        run(game.inventory.scriptUnequipItem(item, on: actor))
    }

    func setOutfit(_ outfit: FormID, on actor: ReferenceKey) -> Bool {
        run(game.inventory.scriptSetOutfit(outfit, on: actor))
    }

    func isEquipped(_ item: FormID, on actor: ReferenceKey) -> Bool? {
        game.inventory.scriptIsEquipped(item, on: actor)
    }

    func equippedWeapon(on actor: ReferenceKey, leftHand: Bool) -> FormID?? {
        game.inventory.scriptEquippedWeapon(on: actor, leftHand: leftHand)
    }

    func equippedShield(on actor: ReferenceKey) -> FormID?? {
        game.inventory.scriptEquippedShield(on: actor)
    }

    func unequipAll(on actor: ReferenceKey) -> Bool {
        run(game.inventory.scriptUnequipAll(on: actor))
    }

    func goldValue(of item: FormID) -> Int32? {
        game.inventory.scriptGoldValue(of: item)
    }
}

extension InventoryWorldAdapter: PapyrusAlchemyBridge {
    func learnIngredientEffects(_ ingredient: FormID, indices: [Int]?) -> Bool {
        game.inventory.learnIngredientEffects(ingredient, indices: indices)
    }

    func learnNextIngredientEffect(_ ingredient: FormID) -> Int? {
        game.inventory.learnNextIngredientEffect(ingredient)
    }

    func isHostileItem(_ item: FormID) -> Bool? {
        game.inventory.isHostileItem(item)
    }
}
