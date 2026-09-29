// Session wiring for faction vendors (issue #506, roadmap item 21.7): turning a
// merchant actor into the barter menu's counterparty, and the rules its vendor
// faction adds to every trade.
//
// The vendor is found and read by the engine's `VendorResolver`; this satellite
// only resolves the merchant chest to an inventory holder, because only the
// streamer knows whether it is resident, and hands `BarterSession` the rules.
//
// The dialogue route needs nothing of its own: the load order's merchant
// topics run a fragment that calls `ShowBarterMenu` on the speaker — on the
// local install 32 of the 39 scripted INFOs conditioned on `JobMerchantFaction`
// do — and that native lands in `openBarter(with:)`.

import AppKit
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyWorld
import OpenSkyWorldState

extension GameViewController {
    /// The engine's vendor reader over the provider's FACT and FLST indexes.
    /// Nil without game data.
    func vendorResolver() -> VendorResolver? {
        guard
            let social = streamerCellProvider as? FactionDataProviding,
            let factions = social.factionStore,
            let formLists = social.formListStore
        else { return nil }
        return VendorResolver(factions: factions, formLists: formLists)
    }

    /// `actor`'s vendor role, from its seeded memberships.
    func vendor(of actor: ReferenceKey) -> Vendor? {
        guard let resolver = vendorResolver() else { return nil }
        if let holder = actorValueHolder(for: actor) {
            seedFactions(of: holder)
        }
        guard let memberships = factions.runtime?.state(of: actor) else { return nil }
        return resolver.vendor(memberships: memberships)
    }

    /// The vendor role one vendor faction describes, or nil when `key` is no
    /// vendor faction this load order carries.
    func vendor(faction key: ReferenceKey) -> Vendor? {
        guard
            let resolver = vendorResolver(),
            let resolved = resolver.factions.faction(key: key),
            resolved.faction.isVendor
        else { return nil }
        return resolver.vendor(faction: resolved)
    }

    /// Opens the barter menu against `actor`'s vendor stock — what
    /// `Actor.ShowBarterMenu` does and what a merchant's dialogue asks for.
    ///
    /// The counterparty is the faction's merchant chest when it names one, and
    /// the actor's own inventory otherwise, which is how the vendors with no
    /// `VENC` trade (UESP's Merchants page: "outside of Hunters, Peddlers, and
    /// Skooma Dealers, merchants rely on merchant chests"). A chest that is not
    /// streamed in is refused rather than read from an empty baseline: its
    /// stock is a leveled list, and inventing an empty shop would be worse
    /// than saying why there is none.
    ///
    /// `override` names a vendor faction to trade under in place of the one
    /// `actor`'s memberships resolve — the dev panel's merchant override
    /// (issue #507), which is how a user checks one faction's hours, list and
    /// chest without finding the actor that carries it.
    ///
    /// - Returns: a readout line, which also lands in the menu's action text.
    @discardableResult
    func openBarter(
        with actor: ReferenceKey,
        vendorFaction override: ReferenceKey? = nil
    ) -> String {
        guard let vendor = override.flatMap(vendor(faction:)) ?? vendor(of: actor) else {
            return noteBarter("\(dialogueSpeakerLabel(for: actor)) is not a merchant.")
        }
        guard let holder = vendorHolder(vendor, actor: actor) else {
            return noteBarter("\(vendor.factionName)'s merchant chest is not streamed in.")
        }
        closeDialogue()
        closeContainerMenuStack()
        containerMenu.container = holder
        containerMenu.containerName = dialogueSpeakerLabel(for: actor)
        containerMenu.containerReference = streamer?.referenceEntry(key: holder.key)?.formID
        containerMenu.vendor = vendor
        containerMenu.mode = .barter
        openContainerMenuStack()
        return noteBarter("Bartering with \(vendor.factionName).")
    }

    /// The rules the current counterparty trades under.
    func barterRules() -> BarterRules {
        guard let vendor = containerMenu.vendor else { return .unrestricted }
        let resolver = vendorResolver()
        let items = worldItems.runtime?.inventory.baselines.items
        let plugin = (streamerCellProvider as? MagicDataProviding)?.magicItemPluginName
        return BarterRules(vendor: vendor, hour: renderer?.gameClock.hourOfDay) { item in
            guard
                let resolver,
                let plugin,
                let raw = items?.definition(item)?.keywords
            else { return [] }
            return resolver.keywords(raw, fromPlugin: plugin)
        }
    }

    private func vendorHolder(_ vendor: Vendor, actor: ReferenceKey) -> InventoryHolder? {
        guard let chest = vendor.merchantChest else {
            guard let placed = streamer?.referenceEntry(key: actor)?.placedActor else {
                return nil
            }
            return InventoryHolder(
                key: actor,
                owner: .actor(base: placed.base),
                cell: streamer?.cellLocation(of: actor)
            )
        }
        guard let placed = streamer?.referenceEntry(key: chest)?.placedReference else {
            return nil
        }
        return InventoryHolder(
            key: chest,
            owner: .container(base: placed.base),
            cell: streamer?.cellLocation(of: chest)
        )
    }

    private func noteBarter(_ text: String) -> String {
        containerMenu.lastActionText = text
        return text
    }
}
