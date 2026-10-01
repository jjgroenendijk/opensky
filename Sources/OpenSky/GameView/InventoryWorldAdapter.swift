// App side of `InventoryCoordinator` and `VendorCoordinator`: builds them from
// the provider, routes the use key, and answers `InventoryWorld` and
// `VendorWorld` from the session systems. The rules live in the coordinators
// (docs/engine/coordinators.md).

import OpenSkyCrime
import OpenSkyFactions
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Answers `InventoryWorld` and `VendorWorld` from the session systems `game` owns.
final class InventoryWorldAdapter {
    unowned let game: GameViewController

    init(game: GameViewController) {
        self.game = game
    }

    /// After the audio and Papyrus subscribers, so the activation sound plays
    /// whether or not the take succeeds.
    func wireWorldItems(provider: any WorldDataProviding, streamer: CellStreamer) {
        guard let items = provider as? ItemDataProviding, let baselines = items.inventoryBaselines
        else { return }
        let coordinator = game.inventory
        coordinator.attach(world: self)
        coordinator.wire(
            inventory: InventoryRuntime(store: game.worldState, baselines: baselines),
            references: streamer,
            catalog: items.equipmentCatalog,
            pricing: (provider as? BarterDataProviding)?.barterPricing
        )
        streamer.onInteraction.add { [weak coordinator] event in
            coordinator?.handleInteraction(event.target.interaction.action)
        }
    }

    /// After `wireFactions`, whose runtime answers the memberships.
    func wireVendors(provider: any WorldDataProviding) {
        guard
            let social = provider as? FactionDataProviding,
            let factionStore = social.factionStore,
            let formLists = social.formListStore
        else { return }
        let core = VendorCore(
            resolver: VendorResolver(factions: factionStore, formLists: formLists),
            itemPluginName: (provider as? MagicDataProviding)?.magicItemPluginName
        )
        game.inventory.vendors = VendorCoordinator(core: core, world: self)
    }
}

extension InventoryWorldAdapter: InventoryWorld {
    var crosshairInteraction: PlacedInteraction? {
        game.hud.interactionTarget?.interaction
    }

    func dropPlacement() -> DropPlacement? {
        guard let renderer = game.renderer, let location = game.streamer?.currentCellLocation
        else { return nil }
        return WorldItemRuntime.dropPlacement(
            in: location,
            eye: renderer.freeFlyCamera.position,
            forward: renderer.freeFlyCamera.forward
        )
    }

    func nearestActorEntry() -> RuntimeReferenceEntry? {
        guard let renderer = game.renderer else { return nil }
        return game.streamer?.nearestActorEntry(to: renderer.freeFlyCamera.position)
    }

    func containerInteractions() -> [PlacedInteraction] {
        game.streamer?.containerInteractions() ?? []
    }

    func appearanceSkipReasons(forActor reference: FormID) -> [String] {
        game.streamer?.appearanceSkipReasons(forActor: reference) ?? []
    }

    func theftBounty(of item: FormID, from reference: ReferenceKey) -> Int32 {
        game.crime.reporter?.theftBounty(of: item, count: 1, from: reference) ?? 0
    }

    func refreshWornEnchantments(on holder: InventoryHolder) {
        game.magic.refreshWornEnchantments(on: holder)
    }

    func enchantmentLine(of item: FormID, on owner: ReferenceKey) -> String? {
        game.magic.enchantmentLine(of: item, on: game.actorValueHolder(for: owner))
    }

    var enchantmentCacheReadout: EnchantmentCacheReadout {
        game.magic.enchantmentCacheReadout
    }
}

extension InventoryWorldAdapter: VendorWorld {
    func factionMemberships(of actor: ReferenceKey) -> ActorFactionState? {
        if let holder = game.actorValueHolder(for: actor) {
            game.seedFactions(of: holder)
        }
        return game.factions.runtime?.state(of: actor)
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
        game.renderer?.gameClock.hourOfDay
    }
}
