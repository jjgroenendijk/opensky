// A follower's trade keeps its starting outfit and its carry weight (UESP "Skyrim:Followers").

import OpenSkyInventory
import Testing

struct TeammateTradeTests {
    @Test func theStartingOutfitStaysButAnExtraCopyMayGo() {
        var facts = TeammateTradeFacts()
        facts.outfit = 1
        facts.carried = 1
        #expect(TeammateTradeRule.refusal(.take, count: 1, facts) == .cannotTakeOutfit)
        facts.carried = 2
        #expect(TeammateTradeRule.refusal(.take, count: 1, facts) == nil)
        #expect(TeammateTradeRule.refusal(.take, count: 2, facts) == .cannotTakeOutfit)
        facts.outfit = 0
        #expect(TeammateTradeRule.refusal(.take, count: 2, facts) == nil)
    }

    @Test func aGiftPastTheCarryWeightIsRefused() {
        var facts = TeammateTradeFacts()
        facts.carriedWeight = 280
        facts.addedWeight = 20
        #expect(TeammateTradeRule.refusal(.store, count: 1, facts) == nil)
        facts.capacity = 300
        #expect(TeammateTradeRule.refusal(.store, count: 1, facts) == nil)
        facts.addedWeight = 21
        #expect(TeammateTradeRule.refusal(.store, count: 1, facts) == .overencumbered)
    }
}
