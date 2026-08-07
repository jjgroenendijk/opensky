// The `iRightHandType` / `iLeftHandType` encoding (issue #403).
//
// These pin the thirteen numbers the vanilla graph counts in, and the one
// conversion that is not the identity. Everything asserted here was read out of
// the user's own install and is cited at the declaration site; the env-gated
// `MeleeCombatRealDataTests` is what proves the vanilla graph agrees.

@testable import opensky
import Testing

struct CombatHandTypeTests {
    @Test func theEncodingIsTheOneWeapEquipSelectsItsEquipClipsBy() {
        // `Weap_Equip_MSG` in `weapequip.hkx` indexes its children off
        // `iRightHandType`, and `MT_LeftHandOverride` in `0_master.hkx` names
        // the same thirteen values as state ids.
        #expect(CombatHandType.handToHand.rawValue == 0)
        #expect(CombatHandType.sword.rawValue == 1)
        #expect(CombatHandType.dagger.rawValue == 2)
        #expect(CombatHandType.axe.rawValue == 3)
        #expect(CombatHandType.mace.rawValue == 4)
        #expect(CombatHandType.greatsword.rawValue == 5)
        #expect(CombatHandType.battleaxe.rawValue == 6)
        #expect(CombatHandType.bow.rawValue == 7)
        #expect(CombatHandType.staff.rawValue == 8)
        #expect(CombatHandType.spell.rawValue == 9)
        #expect(CombatHandType.shield.rawValue == 10)
        #expect(CombatHandType.torch.rawValue == 11)
        #expect(CombatHandType.crossbow.rawValue == 12)
        #expect(CombatHandType.allCases.count == 13)
    }

    @Test func aWeaponsAnimationTypeConvertsRatherThanCasts() {
        #expect(CombatHandType(weapon: .oneHandSword) == .sword)
        #expect(CombatHandType(weapon: .oneHandDagger) == .dagger)
        #expect(CombatHandType(weapon: .oneHandAxe) == .axe)
        #expect(CombatHandType(weapon: .oneHandMace) == .mace)
        #expect(CombatHandType(weapon: .twoHandSword) == .greatsword)
        #expect(CombatHandType(weapon: .twoHandAxe) == .battleaxe)
        #expect(CombatHandType(weapon: .bow) == .bow)
        #expect(CombatHandType(weapon: .staff) == .staff)
    }

    /// The one place the two enums disagree, and the whole reason this is a
    /// conversion: DNAM spells crossbow 9, which the graph reads as a spell.
    @Test func aCrossbowIsNineInTheRecordAndTwelveInTheGraph() {
        #expect(Weapon.AnimationType.crossbow.rawValue == 9)
        #expect(CombatHandType(weapon: .crossbow) == .crossbow)
        #expect(CombatHandType(weapon: .crossbow).rawValue == 12)
    }

    @Test func anUnreadableOrAbsentAnimationTypeReadsAsAnEmptyHand() {
        #expect(CombatHandType(weapon: nil) == .handToHand)
        #expect(CombatHandType(weapon: .other) == .handToHand)
    }

    @Test func theTwoHandedFamiliesMatchTheEquipmentCatalogsOwnSplit() {
        for type in CombatHandType.allCases {
            #expect(type.occupiesBothHands == [.greatsword, .battleaxe, .bow, .crossbow]
                .contains(type))
        }
    }

    @Test func onlyASpellDrawsThroughTheMagicEquip() {
        for type in CombatHandType.allCases {
            #expect(type.drawsAsMagic == (type == .spell))
        }
    }

    @Test func theGraphValueIsTheDeclaredInt32() {
        #expect(CombatHandType.torch.graphValue == .int(11))
    }

    @Test func everyCaseNamesItselfForTheReadout() {
        for type in CombatHandType.allCases {
            #expect(!type.displayName.isEmpty)
        }
        #expect(CombatHandType.sword.displayName == "one-handed sword")
    }
}
