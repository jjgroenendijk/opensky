// Faction vendors (issue #506, roadmap item 21.7): which faction makes an actor
// a merchant, which chest it sells from, when it trades, and what it will buy
// and sell.
//
// ## Sources
//
// The Creation Kit wiki's Faction page, Vendor tab
// (<https://ck.uesp.net/wiki/Faction>), is the source for every rule here:
//
// - "Start Hour/End Hour: These allow you to set what hours of the day the
//   faction members will offer goods."
// - "Vendor Buy/Sell List: ... This is usually a FormList with a set of
//   keywords. The merchant will buy and sell any items which are tagged with
//   keywords contained in this list."
// - "Not Buy/Sell This negates the vendor buy/sell list ... the merchant will
//   buy and sell items that DO NOT match the buy/sell list. ... The pawnbroker
//   Belethor in Whiterun uses VendorItemsMisc as the buy/sell list, and has
//   this checked".
// - "Merchant Container: Sets what container the merchant will sell goods
//   from. Note that a vendor will not sell items in this container unless they
//   also match the vendor's buy/sell list".
// - "Only Buys Stolen Goods: Sets this vendor up to only pay for stolen items
//   the player wants to fence."
//
// The fence reading needs care. Despite the flag's name, UESP's Merchants page
// lists fences as merchants that "are the only merchants who will purchase
// stolen goods" (<https://en.uesp.net/wiki/Skyrim:Merchants>), and on the local
// install every fence faction — `ServicesThievesGuildTonilia` among them — also
// authors Belethor's negated `VendorItemsMisc` list, which would be pointless
// on a vendor that bought nothing honest. So the flag here means "also buys
// stolen goods", and the keyword list still gates everything else. Recorded
// in docs/engine/barter.md.
//
// Observed on the local install (`Skyrim.esm`): 145 vendor factions; hours
// `0-24` on 81 of them and `8-20` on 41; one authors `0-0`, which this engine
// reads as always open because an empty window would make a vendor nobody can
// trade with; one (`WhiterunBanneredMareFaction`) authors no list, which this
// engine reads as no keyword gate.
//
// Documented in docs/engine/barter.md.

import Foundation

/// When a vendor trades, from the `VENV` start and end hours.
nonisolated struct VendorHours: Equatable, Sendable {
    let start: UInt16
    let end: UInt16

    /// Whether `hour` (0 up to 24) falls inside the window.
    ///
    /// Start inclusive, end exclusive. An end of 24 or more runs to midnight; a
    /// start after the end wraps past midnight; a start equal to the end is
    /// read as always open (see the file header).
    func isOpen(atHour hour: Float) -> Bool {
        guard start != end else { return true }
        let open = Float(start)
        let close = Float(min(end, 24))
        if open < close {
            return hour >= open && hour < close
        }
        return hour >= open || hour < close
    }
}

/// One actor's vendor role, resolved from its vendor faction.
nonisolated struct Vendor: Equatable, Sendable {
    let faction: ReferenceKey
    let factionName: String
    /// The `VENC` merchant chest, or nil when the faction names none — then
    /// the vendor sells from its own inventory.
    let merchantChest: ReferenceKey?
    let hours: VendorHours?
    /// Every keyword the `VEND` list names, flattened through nested lists.
    /// Nil when the faction authors no list, which gates nothing.
    let listKeywords: Set<ReferenceKey>?
    /// `VENV`'s "Not Buy/Sell": trade what does *not* match the list.
    let negatesList: Bool
    /// `VENV`'s "Only Buys Stolen Goods": this vendor is a fence.
    let buysStolen: Bool

    /// Whether this vendor buys and sells an item carrying `keywords`.
    func trades(keywords: Set<ReferenceKey>) -> Bool {
        guard let listKeywords else { return true }
        let matches = !listKeywords.isDisjoint(with: keywords)
        return matches != negatesList
    }

    func isOpen(atHour hour: Float) -> Bool {
        hours?.isOpen(atHour: hour) ?? true
    }
}

/// Finds an actor's vendor faction and reads its vendor block.
nonisolated struct VendorResolver {
    let factions: FactionStore
    let formLists: FormListStore

    /// The first vendor faction among `memberships`, in membership order, or
    /// nil when the actor is no merchant.
    ///
    /// Membership order rather than a search for the "best" one: an actor
    /// with two vendor factions — UESP names Adrianne Avenicci, who "is unique
    /// in having access to two merchant chests" — switches between them by
    /// the vendor conditions this engine does not evaluate yet, so the first
    /// authored one is the honest default.
    func vendor(memberships: ActorFactionState) -> Vendor? {
        for membership in memberships.memberships {
            guard
                let resolved = factions.faction(key: membership.faction),
                resolved.faction.isVendor
            else { continue }
            return vendor(faction: resolved)
        }
        return nil
    }

    func vendor(faction resolved: ResolvedFaction) -> Vendor {
        let values = resolved.faction.vendorValues
        return Vendor(
            faction: ReferenceKey(resolved: resolved.id),
            factionName: resolved.displayName,
            merchantChest: factions.linkKey(resolved.faction.merchantContainer, of: resolved),
            hours: values.map { VendorHours(start: $0.startHour, end: $0.endHour) },
            listKeywords: listKeywords(of: resolved),
            negatesList: values?.notSellBuy ?? false,
            buysStolen: values?.onlyBuysStolenItems ?? false
        )
    }

    /// An item's keywords as the same identities the list resolves to.
    func keywords(_ raw: [FormID], fromPlugin pluginName: String) -> Set<ReferenceKey> {
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
}
