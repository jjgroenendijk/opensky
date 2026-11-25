// A follower's trade keeps its starting outfit and its carry weight (UESP "Skyrim:Followers").

import OpenSkyInventory
import OpenSkyInventoryInterface
import Testing

struct TeammateTradeTests {
    /// The game shows no outfit message: the hidden rows keep the outfit instead.
    @Test func aTakeIsNeverRefused() {
        var facts = TeammateTradeFacts()
        facts.capacity = 0
        #expect(TeammateTradeRule.refusal(.take, facts) == nil)
        #expect(TeammateTradeRule.refusal(.buy, facts) == nil)
    }

    @Test func aGiftPastTheCarryWeightIsRefused() {
        var facts = TeammateTradeFacts()
        facts.carriedWeight = 280
        facts.addedWeight = 20
        #expect(TeammateTradeRule.refusal(.store, facts) == nil)
        facts.capacity = 300
        #expect(TeammateTradeRule.refusal(.store, facts) == nil)
        facts.addedWeight = 21
        #expect(TeammateTradeRule.refusal(.store, facts) == .overencumbered)
    }
}
