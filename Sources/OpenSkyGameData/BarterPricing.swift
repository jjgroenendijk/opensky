// Vanilla barter pricing, from UESP "Skyrim:Speech#Prices":
//   price factor = fBarterMax - (fBarterMax - fBarterMin) * min(skill, 100) / 100
//   buy = round(value * buy modifier * factor); sell = round(value * sell modifier / factor)
// Caps: sell at most value * 1.00, buy at least value * 1.05. Both settings come
// from the load order's GMSTs, with vanilla defaults (3.3, 2.0) only when missing.
// See docs/engine/barter.md.

import Foundation
import OpenSkyFormatsESM

/// The barter price factors one merchant transaction is priced at.
nonisolated public struct BarterPricing: Equatable, Sendable {
    /// GMST editor IDs, spelled as the records spell them.
    public static let barterMinSettingName = "fBarterMin"
    public static let barterMaxSettingName = "fBarterMax"

    /// The documented vanilla defaults, used only when the load order does not
    /// describe the setting at all.
    public static let vanillaBarterMin = 2.0
    public static let vanillaBarterMax = 3.3

    /// Speech is capped at 100 in the formula: "skill levels over 100 have no
    /// effect".
    public static let maximumSpeechSkill: Double = 100

    /// The Speech value prices use: 15, the vanilla start. UESP gives it as a worked
    /// example ("At 15 skill and no perks, the final price factor is 3.10 for buying and
    /// 0.322 for selling"), so there is a published value to check.
    public static let defaultSpeechSkill: Double = 15

    /// Trade price caps, from the same section: a merchant never pays more than
    /// the item's value, and never sells below 1.05 times it. Both are dead
    /// weight at vanilla settings — the factor never leaves 2.0...3.3 — and both
    /// become live the moment a plugin retunes `fBarterMin` or a perk lands.
    public static let maximumSellFraction = 1.0
    public static let minimumBuyFraction = 1.05

    public let barterMin: Double
    public let barterMax: Double
    public let speechSkill: Double
    /// The modified price factors that carry perks and Fortify Barter. Both are
    /// 1 for this milestone; see the file comment.
    public let buyModifier: Double
    public let sellModifier: Double

    /// Where `barterMin` and `barterMax` came from, for the verification
    /// readout: the plugin that authored the winning GMST, or the fallback.
    public let source: String

    /// Vanilla settings at the fixed Speech value, for tests, the CLI probe and
    /// any caller with no load order to read.
    public static let vanilla = BarterPricing(
        barterMin: vanillaBarterMin,
        barterMax: vanillaBarterMax,
        source: "documented vanilla default"
    )

    public init(
        barterMin: Double,
        barterMax: Double,
        speechSkill: Double = BarterPricing.defaultSpeechSkill,
        buyModifier: Double = 1,
        sellModifier: Double = 1,
        source: String = "caller"
    ) {
        self.barterMin = barterMin
        self.barterMax = barterMax
        self.speechSkill = speechSkill
        self.buyModifier = buyModifier
        self.sellModifier = sellModifier
        self.source = source
    }

    // MARK: - The formula

    /// `fBarterMax - (fBarterMax - fBarterMin) * min(skill, 100) / 100`.
    ///
    /// Negative Speech clamps to zero as well as positive Speech clamping to
    /// 100: the formula is documented over a skill level, and a skill level
    /// below zero is not one.
    public var basePriceFactor: Double {
        let skill = min(max(speechSkill, 0), Self.maximumSpeechSkill)
        return barterMax - (barterMax - barterMin) * skill / Self.maximumSpeechSkill
    }

    /// What the player pays the merchant for one of an item worth `value`.
    ///
    /// Rounds to the nearest whole number, half away from zero, which is what
    /// `Double.rounded()` does and what "rounds to the nearest whole number"
    /// means in the cited source.
    public func buyPrice(value: Int32) -> Int32 {
        guard value > 0 else { return 0 }
        let base = Double(value)
        let priced = base * buyModifier * basePriceFactor
        return whole(max(priced, base * Self.minimumBuyFraction))
    }

    /// What the merchant pays the player for one of an item worth `value`.
    public func sellPrice(value: Int32) -> Int32 {
        guard value > 0, basePriceFactor > 0 else { return 0 }
        let base = Double(value)
        let priced = base * sellModifier / basePriceFactor
        return whole(min(priced, base * Self.maximumSellFraction))
    }

    /// The price of `count` of an item, priced per unit and then multiplied.
    ///
    /// Per-unit rather than per-stack deliberately: vanilla shows one row one
    /// price, and pricing the stack whole would round once instead of `count`
    /// times and disagree with the row the player is looking at.
    public func buyPrice(value: Int32, count: Int32) -> Int64 {
        Int64(buyPrice(value: value)) * Int64(max(count, 0))
    }

    public func sellPrice(value: Int32, count: Int32) -> Int64 {
        Int64(sellPrice(value: value)) * Int64(max(count, 0))
    }

    /// Rounds and clamps into `Int32`. A price is never negative, and an item
    /// value near `Int32.max` at a factor of 3.3 would otherwise overflow.
    private func whole(_ price: Double) -> Int32 {
        guard price.isFinite else { return 0 }
        return Int32(min(max(price.rounded(), 0), Double(Int32.max)))
    }

    // MARK: - Resolving from game data

    /// Reads `fBarterMin` and `fBarterMax` out of the load order.
    ///
    /// A setting that is absent, non-finite or non-positive falls back to its
    /// documented vanilla default rather than being trusted: a zero price factor
    /// would divide the sell price by zero, and a negative one would pay the
    /// player to buy.
    public static func resolve(
        store: GameSettingStore,
        speechSkill: Double = BarterPricing.defaultSpeechSkill
    ) -> BarterPricing {
        let minimum = float(
            editorID: barterMinSettingName,
            store: store,
            fallback: vanillaBarterMin
        )
        let maximum = float(
            editorID: barterMaxSettingName,
            store: store,
            fallback: vanillaBarterMax
        )
        return BarterPricing(
            barterMin: minimum.value,
            barterMax: maximum.value,
            speechSkill: speechSkill,
            source: "\(barterMinSettingName) \(minimum.source), "
                + "\(barterMaxSettingName) \(maximum.source)"
        )
    }

    private static func float(
        editorID: String,
        store: GameSettingStore,
        fallback: Double
    ) -> (value: Double, source: String) {
        guard
            let resolved = store.setting(editorID: editorID),
            case let .float(value) = resolved.setting.value,
            value.isFinite,
            value > 0
        else {
            return (fallback, "documented vanilla default")
        }
        return (Double(value), resolved.sourcePlugin)
    }
}
