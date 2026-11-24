// Merchant transactions: buying and selling, priced by `BarterPricing` and
// settled through `InventoryRuntime.exchange`, so item and gold move together.
// A merchant is an inventory holder; `BarterRules` adds vendor hours, keywords,
// and fencing. Refusals are typed outcomes that write nothing.
// See docs/engine/barter.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface

/// Why a transaction did not happen.
nonisolated public enum BarterError: Error, Equatable {
    /// The player asked to buy more than the merchant stocks.
    case notStocked(item: FormID, wanted: Int32, available: Int32)
    /// The player asked to sell more than they carry.
    case notCarried(item: FormID, wanted: Int32, available: Int32)
    /// The price is more gold than the player has.
    case playerCannotAfford(price: Int64, gold: Int32)
    /// The merchant's gold stack cannot cover what it offered to pay. This is
    /// the zero-gold merchant, which still sells its whole stock.
    case merchantCannotAfford(price: Int64, gold: Int32)
    /// A count of zero or less. Trading nothing is a caller bug, not a refusal.
    case nonPositiveCount(Int32)
    /// The price exceeds what one gold stack can hold, so no amount of gold in
    /// the world could settle it.
    case priceOutOfRange(Int64)
    /// Outside the vendor faction's `VENV` hours, or a vendor with no hours.
    case vendorClosed(opens: UInt16, closes: UInt16)
    /// The vendor's buy/sell list, with its negation, excludes the item.
    case vendorDoesNotTrade(item: FormID)
    /// Stolen copies offered to a vendor that is not a fence.
    case vendorRefusesStolen(item: FormID, stolen: Int32)
    /// A vendor never buys a key.
    case vendorRefusesKey(item: FormID)
}

/// The vendor rules one session trades under.
nonisolated public struct BarterRules {
    /// The faction vendor, or nil for a nominated container, which trades
    /// anything at any hour and keeps stolen goods stolen.
    public let vendor: Vendor?
    /// The game hour the session trades at, or nil with no clock — which
    /// leaves the hours ungated rather than guessing a time.
    public let hour: Float?
    /// An item's keywords as `Vendor.trades(keywords:)` compares them.
    public let keywords: (FormID) -> Set<ReferenceKey>
    /// The player's bypass values, which open what the vendor buys.
    public var bypass = VendorBypass()

    public static var unrestricted: BarterRules {
        BarterRules(vendor: nil, hour: nil) { _ in [] }
    }

    /// Why this vendor will not trade `item` at all, or nil when it will. On a sale the
    /// keyword bypass skips the list, as the Merchant perk does.
    public func refusal(for item: FormID, selling: Bool = false) -> BarterError? {
        guard let vendor else { return nil }
        if let hour, !vendor.isOpen(atHour: hour) {
            return .vendorClosed(opens: vendor.hours?.start ?? 0, closes: vendor.hours?.end ?? 0)
        }
        if selling, bypass.keywords {
            return nil
        }
        return vendor.trades(keywords: keywords(item)) ? nil : .vendorDoesNotTrade(item: item)
    }

    /// Whether this vendor takes stolen copies: a fence, or the stolen bypass.
    var buysStolen: Bool {
        vendor?.buysStolen == true || bypass.stolen
    }
}

/// What one completed transaction moved.
nonisolated public struct BarterTransaction: Equatable, Sendable {
    public let count: Int32
    /// Total gold that changed hands, already multiplied by `count`.
    public let gold: Int32
    /// One copy's base value. Speech learns from it, once per trade, whatever the
    /// count and price (UESP "Skyrim:Speech").
    public var unitValue: Int32 = 0
}

/// A live buy-and-sell session between the player and one merchant container.
@MainActor
public final class BarterSession {
    /// The container standing in as the merchant's stock and purse.
    public let merchant: InventoryHolder
    public let player: InventoryHolder
    /// The price factors in force. Resolved from the load order's own GMSTs by
    /// the caller, so a plugin that retunes barter retunes this session.
    public let pricing: BarterPricing
    public let rules: BarterRules
    /// A chest vendor's own inventory, which trades beside the chest; nil for any other.
    public var ownStock: InventoryHolder?

    private let runtime: WorldItemRuntime

    private var inventory: InventoryRuntime {
        runtime.inventory
    }

    public init(
        runtime: WorldItemRuntime,
        merchant: InventoryHolder,
        pricing: BarterPricing,
        rules: BarterRules = .unrestricted
    ) {
        self.runtime = runtime
        self.merchant = merchant
        self.pricing = pricing
        self.rules = rules
        player = runtime.player
    }

    // MARK: - Reading

    /// The gold in the chest and in the vendor's own inventory.
    public var merchantGold: Int32 {
        let own = ownStock.map { inventory.goldCount(of: $0) } ?? 0
        return Int32(clamping: Int64(inventory.goldCount(of: merchant)) + Int64(own))
    }

    public var playerGold: Int32 {
        inventory.goldCount(of: player)
    }

    /// What the player would pay for the next one of `item`, the merchant's lowest copy.
    func buyPrice(of item: FormID) -> Int32 {
        Int32(clamping: price(of: item, count: 1, from: merchant, buying: true))
    }

    /// What the merchant would pay for the next one of `item`, the player's lowest copy.
    func sellPrice(of item: FormID) -> Int32 {
        Int32(clamping: price(of: item, count: 1, from: player, buying: false))
    }

    /// The item's gold value with its enchantment, or zero when no loaded plugin
    /// describes the form — the same answer `InventoryRuntime.carriedValue` gives,
    /// because inventing a value would put a number the data never authored into a
    /// price. A tempered copy is worth the UESP value multiplier more, and a made
    /// enchantment adds its own worth.
    private func value(of item: FormID, copy: ItemCopy = .plain) -> Int32 {
        inventory.value(of: item, copy: copy)
    }

    /// The whole price of the `count` copies a move from `holder` takes, each one priced
    /// apart, so a stack rounds as its rows do.
    private func price(
        of item: FormID, count: Int32, from holder: InventoryHolder, buying: Bool
    ) -> Int64 {
        var copies = inventory.leavingCopies(count, of: item, in: holder)
        copies += Array(repeating: .plain, count: max(0, Int(count) - copies.count))
        return copies.reduce(Int64(0)) { total, copy in
            let value = value(of: item, copy: copy)
            let one = buying ? pricing.buyPrice(value: value) : pricing.sellPrice(value: value)
            return total + Int64(one)
        }
    }

    // MARK: - Transactions

    /// Buys `count` of `item` from the merchant. Bought items arrive honest
    /// (<https://en.uesp.net/wiki/Skyrim:Merchants>).
    /// - Throws: `BarterError.notStocked`, `BarterError.playerCannotAfford`, and the
    ///   vendor refusals `BarterRules` names. All write nothing.
    @discardableResult
    public func buy(_ item: FormID, count: Int32 = 1) throws -> BarterTransaction {
        try requirePositive(count)
        if let refusal = rules.refusal(for: item) {
            throw refusal
        }
        let inChest = inventory.count(of: item, in: merchant)
        let own = ownStock.map { inventory.count(of: item, in: $0) } ?? 0
        guard inChest + own >= count else {
            throw BarterError.notStocked(item: item, wanted: count, available: inChest + own)
        }
        // The chest's copies go first, then the vendor's own.
        let legs = [
            (merchant, min(count, inChest)),
            (ownStock ?? merchant, count - min(count, inChest))
        ]
        .filter { $0.1 > 0 }
        var prices: [Int32] = []
        for (holder, legCount) in legs {
            let legPrice = price(of: item, count: legCount, from: holder, buying: true)
            try prices.append(wholePrice(legPrice))
        }
        let price = try wholePrice(prices.reduce(Int64(0)) { $0 + Int64($1) })
        let gold = playerGold
        guard gold >= price else {
            throw BarterError.playerCannotAfford(price: Int64(price), gold: gold)
        }
        for (leg, legPrice) in zip(legs, prices) {
            try inventory.exchange(
                giving: (inventory.goldFormID, legPrice),
                taking: (item, leg.1),
                from: player,
                to: leg.0,
                laundering: rules.vendor != nil
            )
        }
        inventory.countBarter()
        return BarterTransaction(count: count, gold: price, unitValue: value(of: item))
    }

    /// Sells `count` of `item` to the merchant. Honest copies go first. A non-fence
    /// refuses stolen copies; a fence takes them in honest. `acceptingLess` sells
    /// for all the merchant's gold when it has less than the price, as the game's
    /// `sNotEnoughVendorGold` question allows.
    /// - Throws: `BarterError.notCarried`, `BarterError.merchantCannotAfford`, and
    ///   the vendor refusals `BarterRules` names. All write nothing.
    @discardableResult
    public func sell(
        _ item: FormID, count: Int32 = 1, acceptingLess: Bool = false
    ) throws -> BarterTransaction {
        try requirePositive(count)
        if rules.vendor != nil, inventory.baselines.items.definition(item)?.family == .key {
            throw BarterError.vendorRefusesKey(item: item)
        }
        if let refusal = rules.refusal(for: item, selling: true) {
            throw refusal
        }
        let available = inventory.count(of: item, in: player)
        guard available >= count else {
            throw BarterError.notCarried(item: item, wanted: count, available: available)
        }
        let stolen = inventory.inventory(of: player).split(taking: count, of: item).stolen
        if rules.vendor != nil, stolen > 0, !rules.buysStolen {
            throw BarterError.vendorRefusesStolen(item: item, stolen: stolen)
        }
        let asked = try wholePrice(price(of: item, count: count, from: player, buying: false))
        let gold = merchantGold
        guard gold >= asked || acceptingLess else {
            throw BarterError.merchantCannotAfford(price: Int64(asked), gold: gold)
        }
        let price = min(asked, max(0, gold))
        try gatherGold(price)
        try inventory.exchange(
            giving: (item, count),
            taking: (inventory.goldFormID, price),
            from: player,
            to: merchant,
            laundering: rules.vendor?.buysStolen == true
        )
        inventory.countBarter()
        return BarterTransaction(count: count, gold: price, unitValue: value(of: item))
    }

    /// Moves gold from the vendor's own inventory into the chest when the chest alone
    /// cannot pay `price`.
    private func gatherGold(_ price: Int32) throws {
        let short = price - inventory.goldCount(of: merchant)
        guard short > 0, let ownStock else { return }
        let moved = min(short, inventory.goldCount(of: ownStock))
        guard moved > 0 else { return }
        try inventory.transfer(inventory.goldFormID, count: moved, from: ownStock, to: merchant)
    }

    private func requirePositive(_ count: Int32) throws {
        guard count > 0 else {
            throw BarterError.nonPositiveCount(count)
        }
    }

    /// Narrows a stack price to the width one gold stack is counted in. A price
    /// that does not fit is refused rather than truncated, because a truncated
    /// price is a silently wrong one.
    private func wholePrice(_ price: Int64) throws -> Int32 {
        guard price <= Int64(Int32.max) else {
            throw BarterError.priceOutOfRange(price)
        }
        return Int32(max(price, 0))
    }
}
