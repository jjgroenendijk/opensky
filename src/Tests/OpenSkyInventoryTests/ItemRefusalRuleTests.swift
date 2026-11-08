// The item actions refused with a notice: drops, quest items, gear changes mid-attack,
// and favourites.

@testable import OpenSkyInventory
import Testing

struct ItemRefusalRuleTests {
    @Test func aDropRefusesKeysQuestItemsAndTheAir() {
        var facts = ItemRequestFacts()
        #expect(ItemRefusalRule.refusal(.drop, facts) == nil)
        facts.playerIsAirborne = true
        #expect(ItemRefusalRule.refusal(.drop, facts) == .dropInAir)
        facts.isKey = true
        #expect(ItemRefusalRule.refusal(.drop, facts) == .dropKey)
        facts.isQuestItem = true
        #expect(ItemRefusalRule.refusal(.drop, facts) == .dropQuestItem)
        #expect(ItemRefusalRule.refusal(.consume, facts) == .eatQuestItem)
    }

    @Test func anAttackBlocksGearChanges() {
        var facts = ItemRequestFacts()
        facts.playerIsAttacking = true
        #expect(ItemRefusalRule
            .refusal(.equip(isArmour: true), facts) == .equipArmourWhileAttacking)
        #expect(ItemRefusalRule
            .refusal(.equip(isArmour: false), facts) == .equipWeaponWhileAttacking)
        #expect(ItemRefusalRule.refusal(.unequip, facts) == .unequipWhileAttacking)
        facts.isEquipped = true
        #expect(ItemRefusalRule.refusal(.drop, facts) == .dropWhileActing)
    }

    @Test func onlySomeFamiliesBecomeFavourites() {
        var facts = ItemRequestFacts()
        #expect(ItemRefusalRule.refusal(.favourite, facts) == nil)
        facts.canBeFavourite = false
        #expect(ItemRefusalRule.refusal(.favourite, facts) == .cannotFavourite)
    }
}
