// Vanilla barter pricing (issue #179) against the published worked examples.
//
// Source for every expectation here: UESP "Skyrim:Speech", section "Prices"
// (https://en.uesp.net/wiki/Skyrim:Speech#Prices). The three factor values and
// the two trade price caps are quoted numbers from that page, not values this
// implementation produced and then had a test written around.

import Foundation
@testable import opensky
import Testing

struct BarterPricingTests {
    /// "price factor = fBarterMax - (fBarterMax - fBarterMin) * min(skill,100)/100",
    /// with the page's own tabulated results: 3.3 at 0 skill, 3.10 at 15, 2 at 100.
    @Test
    func basePriceFactorMatchesTheDocumentedCurve() {
        #expect(pricing(speech: 0).basePriceFactor == 3.3)
        #expect(abs(pricing(speech: 15).basePriceFactor - 3.105) < 1e-9)
        #expect(abs(pricing(speech: 100).basePriceFactor - 2.0) < 1e-9)
    }

    /// "Skill levels over 100 have no effect", and a level below zero is not a
    /// skill level at all.
    @Test
    func speechIsClampedAtBothEnds() {
        #expect(pricing(speech: 500).basePriceFactor == pricing(speech: 100).basePriceFactor)
        #expect(pricing(speech: -20).basePriceFactor == pricing(speech: 0).basePriceFactor)
    }

    /// The milestone prices at the vanilla starting Speech of 15, which is the
    /// value the source tabulates: 3.10 buying, 0.322 selling.
    @Test
    func defaultSpeechIsTheStartingSkill() {
        let vanilla = BarterPricing.vanilla
        #expect(vanilla.speechSkill == 15)
        #expect(abs(vanilla.basePriceFactor - 3.105) < 1e-9)
        #expect(abs(1 / vanilla.basePriceFactor - 0.3221) < 1e-4)
    }

    /// "buy price = round(value of item * buy price modifier * base price factor)"
    /// and "sell price = round(value of item * sell price modifier / base price
    /// factor)", rounding to the nearest whole number.
    @Test
    func pricesRoundToTheNearestWholeNumber() {
        let vanilla = BarterPricing.vanilla
        // 125 * 3.105 = 388.125 -> 388; 125 / 3.105 = 40.257 -> 40.
        #expect(vanilla.buyPrice(value: 125) == 388)
        #expect(vanilla.sellPrice(value: 125) == 40)
        // 10 * 3.105 = 31.05 -> 31; 10 / 3.105 = 3.22 -> 3.
        #expect(vanilla.buyPrice(value: 10) == 31)
        #expect(vanilla.sellPrice(value: 10) == 3)
        // Half rounds away from zero: 100 * 2.0 at Speech 100 is exact, and a
        // .5 case comes from a value of 1 at a factor of 2.5.
        #expect(pricing(minimum: 2.5, maximum: 2.5).buyPrice(value: 1) == 3)
    }

    /// A merchant at the two ends of the Speech curve, so the sign of the
    /// relationship is pinned: higher Speech buys cheaper and sells dearer.
    @Test
    func higherSpeechIsStrictlyBetterForThePlayer() {
        let novice = pricing(speech: 0)
        let master = pricing(speech: 100)
        #expect(master.buyPrice(value: 200) < novice.buyPrice(value: 200))
        #expect(master.sellPrice(value: 200) > novice.sellPrice(value: 200))
    }

    /// "Trade price cap: (max sell price = value * 1.00), (min buy price =
    /// value * 1.05)." Unreachable at vanilla settings, reachable the moment a
    /// plugin retunes the two GMSTs, which is what this drives.
    @Test
    func tradePriceCapsBind() {
        let generous = pricing(minimum: 0.5, maximum: 0.5)
        #expect(generous.buyPrice(value: 100) == 105, "the minimum buy price is value * 1.05")
        #expect(generous.sellPrice(value: 100) == 100, "the maximum sell price is value")
    }

    /// A stack is priced per unit and multiplied, so the row price the player
    /// reads and the total they pay cannot disagree by a rounding step.
    @Test
    func stackPricesAreTheUnitPriceMultiplied() {
        let vanilla = BarterPricing.vanilla
        #expect(vanilla.buyPrice(value: 10, count: 7) == 217)
        #expect(vanilla.sellPrice(value: 10, count: 7) == 21)
        #expect(vanilla.buyPrice(value: 10, count: 0) == 0)
        #expect(vanilla.buyPrice(value: 10, count: -3) == 0, "a negative count prices nothing")
    }

    /// A worthless item trades for nothing rather than for a fabricated
    /// minimum, and a form no plugin describes reaches here as value zero.
    @Test
    func worthlessItemsCostNothing() {
        #expect(BarterPricing.vanilla.buyPrice(value: 0) == 0)
        #expect(BarterPricing.vanilla.sellPrice(value: 0) == 0)
        #expect(BarterPricing.vanilla.buyPrice(value: -5) == 0)
    }

    /// A huge value at a factor above 3 would overflow `Int32`; the price
    /// saturates rather than wrapping into a negative one.
    @Test
    func extremeValuesSaturateRatherThanWrap() {
        #expect(BarterPricing.vanilla.buyPrice(value: .max) == .max)
    }

    // MARK: - Resolution from game data

    @Test
    func settingsComeFromTheLoadOrder() throws {
        let store = try settingStore(minimum: 1.5, maximum: 4.0)
        let resolved = BarterPricing.resolve(store: store)
        #expect(resolved.barterMin == 1.5)
        #expect(resolved.barterMax == 4.0)
        #expect(resolved.source.contains("Tuning.esp"))
        // 4.0 - 2.5 * 15/100 = 3.625.
        #expect(abs(resolved.basePriceFactor - 3.625) < 1e-9)
    }

    /// A plugin that sets a nonsense factor is not trusted: a zero factor would
    /// divide the sell price by zero and a negative one would pay the player to
    /// buy, so the documented vanilla default stands instead.
    @Test
    func nonPositiveSettingsFallBackToTheVanillaDefaults() throws {
        let resolved = try BarterPricing.resolve(store: settingStore(minimum: 0, maximum: -1))
        #expect(resolved.barterMin == BarterPricing.vanillaBarterMin)
        #expect(resolved.barterMax == BarterPricing.vanillaBarterMax)
        #expect(resolved.source.contains("documented vanilla default"))
    }

    @Test
    func absentSettingsFallBackToTheVanillaDefaults() {
        let resolved = BarterPricing.resolve(store: GameSettingStore(plugins: []))
        #expect(resolved.barterMin == BarterPricing.vanillaBarterMin)
        #expect(resolved.barterMax == BarterPricing.vanillaBarterMax)
    }

    // MARK: - Fixtures

    private func pricing(speech: Double) -> BarterPricing {
        BarterPricing(
            barterMin: BarterPricing.vanillaBarterMin,
            barterMax: BarterPricing.vanillaBarterMax,
            speechSkill: speech
        )
    }

    private func pricing(minimum: Double, maximum: Double) -> BarterPricing {
        BarterPricing(barterMin: minimum, barterMax: maximum)
    }

    /// A synthetic plugin carrying just the two GMSTs, built in code — never an
    /// extracted record. Same shape `GameSettingStoreTests` builds.
    private func settingStore(minimum: Float, maximum: Float) throws -> GameSettingStore {
        let records = setting(BarterPricing.barterMinSettingName, value: minimum, formID: 1)
            + setting(BarterPricing.barterMaxSettingName, value: maximum, formID: 2)
        let file = try ESMFile(
            data: ESMFixture.tes4() + ESMFixture.topGroup("GMST", contents: records)
        )
        return GameSettingStore(plugins: [("Tuning.esp", file)])
    }

    private func setting(_ editorID: String, value: Float, formID: UInt32) -> Data {
        var raw = value.bitPattern.littleEndian
        let data = withUnsafeBytes(of: &raw) { Data($0) }
        let fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
            + ESMFixture.field("DATA", data)
        return ESMFixture.record("GMST", formID: formID, data: fields)
    }
}
