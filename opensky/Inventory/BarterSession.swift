// Merchant transactions (M12.2.3, issue #179): buying from and selling to a
// merchant, priced by `BarterPricing` and settled through `InventoryRuntime`.
//
// A merchant here is a container reference. Vanilla merchants sell from a
// faction-linked chest and none of that faction data is decoded yet, so this
// milestone's merchant is a container the developer nominates from the sidebar.
// The session takes an `InventoryHolder` and does not care how it was chosen,
// which is what lets the faction-driven answer replace the nomination later
// without touching anything here.
//
// Every transaction is one `InventoryRuntime.exchange`, so the item and the gold
// move together or not at all, and both land in the world-state journal, the
// dirty counts and the save exactly like any other inventory write.
//
// Refusals are ordinary outcomes, not errors in the sense of something having
// gone wrong: a merchant with no gold buys nothing and still sells everything,
// and a player who cannot afford a sword is not a fault. They are typed so the
// menu can say which refusal it was, and every one of them writes nothing.
//
// Documented in docs/engine/barter.md.

import Foundation

/// Why a transaction did not happen.
nonisolated enum BarterError: Error, Equatable {
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
}

/// What one completed transaction moved.
nonisolated struct BarterTransaction: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        /// Gold player to merchant, item merchant to player.
        case buy
        /// Item player to merchant, gold merchant to player.
        case sell
    }

    let kind: Kind
    let item: FormID
    let count: Int32
    /// Total gold that changed hands, already multiplied by `count`.
    let gold: Int32
}

/// A live buy-and-sell session between the player and one merchant container.
@MainActor
final class BarterSession {
    /// The container standing in as the merchant's stock and purse.
    let merchant: InventoryHolder
    let player: InventoryHolder
    /// The price factors in force. Resolved from the load order's own GMSTs by
    /// the caller, so a plugin that retunes barter retunes this session.
    let pricing: BarterPricing

    private let runtime: WorldItemRuntime

    private var inventory: InventoryRuntime {
        runtime.inventory
    }

    init(runtime: WorldItemRuntime, merchant: InventoryHolder, pricing: BarterPricing) {
        self.runtime = runtime
        self.merchant = merchant
        self.pricing = pricing
        player = runtime.player
    }

    // MARK: - Reading

    /// What the merchant has for sale right now, read through the runtime on
    /// every access rather than cached, like `ContainerSession.contents`.
    var stock: [InventoryStack] {
        inventory.inventory(of: merchant).stacks
    }

    var merchantGold: Int32 {
        inventory.goldCount(of: merchant)
    }

    var playerGold: Int32 {
        inventory.goldCount(of: player)
    }

    /// What the player would pay for one of `item`.
    func buyPrice(of item: FormID) -> Int32 {
        pricing.buyPrice(value: value(of: item))
    }

    /// What the merchant would pay for one of `item`.
    func sellPrice(of item: FormID) -> Int32 {
        pricing.sellPrice(value: value(of: item))
    }

    /// The item's base gold value, or zero when no loaded plugin describes the
    /// form — the same answer `InventoryRuntime.carriedValue` gives, because
    /// inventing a value for an unknown form would put a number the data never
    /// authored into a price.
    private func value(of item: FormID) -> Int32 {
        inventory.baselines.items.definition(item)?.value ?? 0
    }

    // MARK: - Transactions

    /// Buys `count` of `item` from the merchant.
    ///
    /// - Throws: `BarterError.notStocked` when the merchant holds fewer,
    ///   `BarterError.playerCannotAfford` when the price exceeds the player's
    ///   gold. Both write nothing.
    @discardableResult
    func buy(_ item: FormID, count: Int32 = 1) throws -> BarterTransaction {
        try requirePositive(count)
        let available = inventory.count(of: item, in: merchant)
        guard available >= count else {
            throw BarterError.notStocked(item: item, wanted: count, available: available)
        }
        let price = try wholePrice(pricing.buyPrice(value: value(of: item), count: count))
        let gold = playerGold
        guard gold >= price else {
            throw BarterError.playerCannotAfford(price: Int64(price), gold: gold)
        }
        try inventory.exchange(
            giving: (inventory.goldFormID, price),
            taking: (item, count),
            from: player,
            to: merchant
        )
        return BarterTransaction(kind: .buy, item: item, count: count, gold: price)
    }

    /// Sells `count` of `item` to the merchant.
    ///
    /// - Throws: `BarterError.notCarried` when the player holds fewer,
    ///   `BarterError.merchantCannotAfford` when the merchant's purse cannot
    ///   cover the offer. Both write nothing.
    @discardableResult
    func sell(_ item: FormID, count: Int32 = 1) throws -> BarterTransaction {
        try requirePositive(count)
        let available = inventory.count(of: item, in: player)
        guard available >= count else {
            throw BarterError.notCarried(item: item, wanted: count, available: available)
        }
        let price = try wholePrice(pricing.sellPrice(value: value(of: item), count: count))
        let gold = merchantGold
        guard gold >= price else {
            throw BarterError.merchantCannotAfford(price: Int64(price), gold: gold)
        }
        try inventory.exchange(
            giving: (item, count),
            taking: (inventory.goldFormID, price),
            from: player,
            to: merchant
        )
        return BarterTransaction(kind: .sell, item: item, count: count, gold: price)
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
