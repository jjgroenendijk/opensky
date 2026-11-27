// Which ATKD attacks an actor uses, over synthetic NPC_ records.
// Rules: docs/engine/attack-data.md.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct ActorAttackListTests {
    private static func attack(_ event: String, damage: Float = 1) -> RaceAttack {
        var properties = RaceAttack.Properties()
        properties.damageMultiplier = damage
        return RaceAttack(properties: properties, event: event)
    }

    /// One ATKD + ATKE pair as record fields.
    private static func fields(_ event: String, damage: Float) -> Data {
        var data = Data()
        data.appendFloat32(damage)
        for value: Float in [1] {
            data.appendFloat32(value)
        }
        data.appendUInt32(0) // spell
        data.appendUInt32(0x4) // flags: power attack
        for value: Float in [0, 35, 0] {
            data.appendFloat32(value)
        }
        data.appendUInt32(0) // keyword
        for value: Float in [0, 0, 2] {
            data.appendFloat32(value)
        }
        return ESMFixture.field("ATKD", data) + ESMFixture.field("ATKE", ESMFixture.zstring(event))
    }

    @Test func theAttackRaceDropsAndAddsAttacks() throws {
        let own = [Self.attack("attackStart", damage: 2), Self.attack("bite")]
        let race = [Self.attack("AttackStart"), Self.attack("bashStart")]
        let merged = try #require(ActorAttackList.merge(own: own, attackRace: race))
        #expect(merged.map(\.event) == ["attackStart", "bashStart"])
        #expect(ActorAttackList.attack(merged, event: "ATTACKSTART")?.damageMultiplier == 2)
        #expect(ActorAttackList.merge(own: [], attackRace: nil) == nil)
        #expect(ActorAttackList.merge(own: [], attackRace: race)?.count == 2)
    }

    /// With the Attack Data flag the template's own list wins; without one, the NPC
    /// falls back to its race's.
    @Test func theAttackDataFlagTakesTheTemplatesList() throws {
        let template = try ActorBase(record: FactionFixture.decode(FactionFixture.actor(
            formID: 0x600, editorID: "Template",
            aiData: Self.fields("attackPowerStart", damage: 3)
        )), localized: false)
        let inheriting = try ActorBase(record: FactionFixture.decode(FactionFixture.actor(
            formID: 0x601, editorID: "Inheriting", templateFlags: 0x0800, template: 0x600,
            aiData: Self.fields("attackStart", damage: 5)
        )), localized: false)
        let plain = try ActorBase(record: FactionFixture.decode(FactionFixture.actor(
            formID: 0x602, editorID: "Plain"
        )), localized: false)
        let resolver = ActorValueResolver(
            templates: ActorTemplateResolver(
                actors: Dictionary(uniqueKeysWithValues: [template, inheriting, plain].map {
                    ($0.formID.rawValue, $0)
                }),
                leveledActors: [:]
            ),
            races: [:]
        )
        let inherited = resolver.attacks(base: FormID(0x601), race: nil)
        #expect(inherited.map(\.event) == ["attackPowerStart"])
        #expect(inherited.first?.properties?.flags.contains(.powerAttack) == true)
        #expect(inherited.first?.properties?.staminaMultiplier == 2)
        #expect(resolver.attacks(base: FormID(0x602), race: nil).isEmpty)
    }
}
