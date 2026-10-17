// The refusals of a barter the player or the merchant cannot pay for, from the
// `sItemTooExpensive` and `sNotEnoughVendorGold` string settings. See docs/engine/barter.md.

import OpenSkyFormatsESM

nonisolated public struct TradeTexts: Equatable, Sendable {
    public var tooExpensive = "You do not have enough gold."
    /// `%d` is the price, then the merchant's gold.
    public var merchantShort = "The price is %d gold; the merchant has %d gold."

    public static let vanilla = Self()

    public init() {}

    public func merchantShortText(price: Int64, gold: Int32) -> String {
        SettingTextFormat.fill(merchantShort, ["\(price)", "\(gold)"])
    }

    public static func resolve(
        store: GameSettingStore, text: (LString) -> String? = { _ in nil }
    ) -> Self {
        var texts = vanilla
        store.read("sItemTooExpensive", into: &texts, \.tooExpensive, text: text)
        store.read("sNotEnoughVendorGold", into: &texts, \.merchantShort, text: text)
        return texts
    }
}
