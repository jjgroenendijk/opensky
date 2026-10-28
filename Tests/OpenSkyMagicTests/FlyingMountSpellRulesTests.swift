// The spells a dragon rider casts: aimed and self spells pass; summons, placed spells,
// and hostile self-centred areas do not.

import Foundation
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyMagic
import Testing

@MainActor
struct FlyingMountSpellRulesTests {
    private static let summonEffect: UInt32 = 0x0900
    private static let summon: UInt32 = 0x0910
    private static let fireStorm: UInt32 = 0x0920
    private static let rune: UInt32 = 0x0930
    private static let grandHealing: UInt32 = 0x0940

    private func store() throws -> SpellStore {
        typealias Fixture = SpellbookFixture
        let extra = [
            Fixture.magicEffect(
                formID: Self.summonEffect, editorID: "SummonFamiliar",
                data: Fixture.effectData(archetype: 18)
            ),
            Fixture.spell(
                formID: Self.summon, editorID: "ConjureFamiliar",
                equipType: Fixture.Slot.eitherHand,
                spit: Fixture.spit(type: 0, chargeTime: 0.5, casting: 1, delivery: 2),
                effects: [.init(Self.summonEffect, 1, 60)]
            ),
            Fixture.spell(
                formID: Self.fireStorm, editorID: "FireStorm", equipType: Fixture.Slot.bothHands,
                spit: Fixture.spit(type: 0, chargeTime: 2, casting: 1, delivery: 0),
                effects: [.init(Fixture.fireDamage, 100, 0, area: 50)]
            ),
            Fixture.spell(
                formID: Self.rune, editorID: "FireRune", equipType: Fixture.Slot.eitherHand,
                spit: Fixture.spit(type: 0, chargeTime: 1, casting: 1, delivery: 4),
                effects: [.init(Fixture.fireDamage, 60, 0)]
            ),
            Fixture.spell(
                formID: Self.grandHealing, editorID: "GrandHealing",
                equipType: Fixture.Slot.eitherHand,
                spit: Fixture.spit(type: 0, chargeTime: 1, casting: 1, delivery: 0),
                effects: [.init(Fixture.restoreHealth, 100, 0, area: 15)]
            )
        ]
        return try SpellStore(index: Fixture.index(extraRecords: extra))
    }

    @Test func aimedAndFriendlySelfSpellsCastFromADragon() throws {
        let spells = try store()
        for name in ["Fireball", "Firebolt", "FastHealing", "Healing", "GrandHealing"] {
            let spell = try #require(spells.spell(editorID: name))
            #expect(FlyingMountSpellRules.allows(spell), "\(name)")
        }
    }

    @Test func summonsPlacedSpellsAndHostileSelfAreasDoNot() throws {
        let spells = try store()
        for name in ["ConjureFamiliar", "FireStorm", "FireRune"] {
            let spell = try #require(spells.spell(editorID: name))
            #expect(!FlyingMountSpellRules.allows(spell), "\(name)")
        }
    }

    @Test func theRefusalShowsTheDragonbornMessage() {
        #expect(CastNoticeText.notice(for: .notFromFlyingMount) == .flyingMountNoCast)
        #expect(CastNoticeText.flyingMountNoCast.rawValue == "sTESVDLC2FlyingDragonNoCastMessage")
    }
}
