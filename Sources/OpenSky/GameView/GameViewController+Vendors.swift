// App shell for `VendorCoordinator`: builds it, answers its `VendorWorld`
// reads, and opens the barter menu it resolves. The rules live in the
// coordinator (docs/engine/coordinators.md).
//
// Merchant dialogue needs nothing here: its fragments call `ShowBarterMenu`
// on the speaker, and that native lands in `openBarter(with:)`.

import AppKit
import OpenSkyFactions
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyWorld
import OpenSkyWorldState

extension GameViewController {
    /// Wired after `wireFactions`, whose runtime answers the memberships.
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
        vendors = VendorCoordinator(core: core, world: self)
    }

    /// Opens the barter menu against `actor`'s vendor stock, which is what
    /// `Actor.ShowBarterMenu` does. `override` is the dev panel's vendor faction.
    ///
    /// - Returns: a readout line, which also lands in the menu's action text.
    @discardableResult
    func openBarter(
        with actor: ReferenceKey,
        vendorFaction override: ReferenceKey? = nil
    ) -> String {
        let result = vendors?.counterparty(for: actor, vendorFaction: override)
            ?? .failure(.notAMerchant)
        let counterparty: BarterCounterparty
        switch result {
        case let .success(found):
            counterparty = found
        case .failure(.notAMerchant):
            return noteBarter("\(dialogueSpeakerLabel(for: actor)) is not a merchant.")
        case let .failure(.chestNotResident(factionName)):
            return noteBarter("\(factionName)'s merchant chest is not streamed in.")
        }
        closeDialogue()
        closeContainerMenuStack()
        containerMenu.container = counterparty.holder
        containerMenu.containerName = dialogueSpeakerLabel(for: actor)
        containerMenu.containerReference = streamer?
            .referenceEntry(key: counterparty.holder.key)?.formID
        containerMenu.vendor = counterparty.vendor
        containerMenu.mode = .barter
        openContainerMenuStack()
        return noteBarter("Bartering with \(counterparty.vendor.factionName).")
    }

    private func noteBarter(_ text: String) -> String {
        containerMenu.lastActionText = text
        return text
    }
}

extension GameViewController: VendorWorld {
    func factionMemberships(of actor: ReferenceKey) -> ActorFactionState? {
        if let holder = actorValueHolder(for: actor) {
            seedFactions(of: holder)
        }
        return factions.runtime?.state(of: actor)
    }

    func residentOwner(of key: ReferenceKey) -> InventoryOwner? {
        guard let entry = streamer?.referenceEntry(key: key) else { return nil }
        if let actor = entry.placedActor {
            return .actor(base: actor.base)
        }
        return entry.placedReference.map { .container(base: $0.base) }
    }

    func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        streamer?.cellLocation(of: key)
    }

    func itemKeywords(of item: FormID) -> [FormID]? {
        worldItems.runtime?.inventory.baselines.items.definition(item)?.keywords
    }

    var hourOfDay: Float? {
        renderer?.gameClock.hourOfDay
    }
}
