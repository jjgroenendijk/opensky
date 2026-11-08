// The barter refusals from the trade settings, with the price and the merchant's gold filled in.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct TradeTextsTests {
    @Test func theMerchantLineFillsThePriceAndTheGold() throws {
        let store = try GameSettingFixture.store([
            "sNotEnoughVendorGold": .text("Value: %d gold. Vendor has %d gold."),
            "sItemTooExpensive": .text("Too dear.")
        ])
        let texts = TradeTexts.resolve(store: store) { text in
            guard case let .inline(value) = text.text else { return nil }
            return value
        }
        #expect(texts.merchantShortText(price: 8, gold: 1) == "Value: 8 gold. Vendor has 1 gold.")
        #expect(texts.tooExpensive == "Too dear.")
    }
}
