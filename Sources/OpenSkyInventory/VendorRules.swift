// Faction vendors: which faction makes a merchant, its chest, hours, place,
// conditions, and what it trades, all per the Vendor tab
// (<https://ck.uesp.net/wiki/Faction>). "Only Buys Stolen Goods" means "also buys
// stolen goods" here: every fence faction on this install also authors a keyword
// list. No list means no keyword gate. See docs/engine/vendor-factions.md.

import Foundation
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

/// Finds an actor's vendor faction and reads its vendor block.
nonisolated public struct VendorResolver: Sendable {
    public let factions: FactionStore
    public let formLists: FormListStore

    /// The first vendor faction in membership order, or nil.
    public func vendor(memberships: ActorFactionState) -> Vendor? {
        vendors(memberships: memberships).first
    }

    /// Every vendor faction in membership order. An actor with two trades as the
    /// first one whose hours, place, and conditions hold now.
    public func vendors(memberships: ActorFactionState) -> [Vendor] {
        memberships.memberships.compactMap { membership in
            guard
                let resolved = factions.faction(key: membership.faction),
                resolved.faction.isVendor
            else { return nil }
            return vendor(faction: resolved)
        }
    }

    public func vendor(faction resolved: ResolvedFaction) -> Vendor {
        let values = resolved.faction.vendorValues
        var vendor = Vendor(
            faction: ReferenceKey(resolved: resolved.id),
            factionName: resolved.displayName,
            merchantChest: factions.linkKey(resolved.faction.merchantContainer, of: resolved),
            hours: values.map { VendorHours(start: $0.startHour, end: $0.endHour) },
            listKeywords: listKeywords(of: resolved),
            negatesList: values?.notSellBuy ?? false,
            buysStolen: values?.onlyBuysStolenItems ?? false
        )
        vendor.location = resolved.faction.vendorLocation.map { location in
            VendorLocationRule(
                place: VendorPlace(
                    type: location.type,
                    link: factions.linkKey(FormID(location.value), of: resolved)
                ),
                radius: Float(values?.radius ?? 0)
            )
        }
        vendor.conditions = resolved.faction.vendorConditions
        vendor.sourcePlugin = resolved.sourcePlugin
        return vendor
    }

    /// An item's keywords as the same identities the list resolves to.
    public func keywords(_ raw: [FormID], fromPlugin pluginName: String) -> Set<ReferenceKey> {
        Set(raw.compactMap {
            formLists.resolvedID($0, fromPlugin: pluginName).map(ReferenceKey.init(resolved:))
        })
    }

    private func listKeywords(of resolved: ResolvedFaction) -> Set<ReferenceKey>? {
        guard
            let link = resolved.faction.vendorBuySellList,
            let id = formLists.resolvedID(link, fromPlugin: resolved.sourcePlugin),
            let flattened = formLists.flattened(id)
        else { return nil }
        return Set(flattened.entries.compactMap { $0.map(ReferenceKey.init(resolved:)) })
    }

    public init(factions: FactionStore, formLists: FormListStore) {
        self.factions = factions
        self.formLists = formLists
    }
}
