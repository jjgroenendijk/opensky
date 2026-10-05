// Difficulty: the damage ratio by level, the GMST overrides, and the Destruction
// experience rule. Fallback values are the UESP "Skyrim:Damage" table.

import FormatsTesting
import Foundation
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import Testing

struct DifficultySettingsTests {
    @Test func damageScalesOnlyBetweenThePlayerAndOthers() {
        let master = DifficultySettings.synthetic.multipliers(.master)
        #expect(DifficultyDamage.scaled(
            10, attackerIsPlayer: true, targetIsPlayer: false, multipliers: master
        ) == 5)
        #expect(DifficultyDamage.scaled(
            10, attackerIsPlayer: false, targetIsPlayer: true, multipliers: master
        ) == 20)
        #expect(DifficultyDamage.scaled(
            10, attackerIsPlayer: false, targetIsPlayer: false, multipliers: master
        ) == 10)
    }

    @Test func aStoredIndexOutOfRangeIsAdept() {
        #expect(DifficultyLevel(index: 5) == .legendary)
        #expect(DifficultyLevel(index: 9) == .adept)
        #expect(DifficultyLevel(index: -1) == .adept)
    }

    @Test func aPluginGMSTOverridesTheTableAndANegativeOneIsIgnored() throws {
        let records = Self.setting("fDiffMultHPToPCL", value: 4, formID: 1)
            + Self.setting("fDiffMultHPByPCL", value: -1, formID: 2)
            + Self.setting("fDiffMultXPL", value: 2, formID: 3)
        let file = try ESMFile(
            data: ESMFixture.tes4() + ESMFixture.topGroup("GMST", contents: records)
        )
        let settings = DifficultySettings.resolve(
            store: GameSettingStore(plugins: [("Tuning.esp", file)])
        )
        let legendary = settings.multipliers(.legendary)
        #expect(legendary.damageToPlayer.value == 4)
        #expect(legendary.damageToPlayer.source == "Tuning.esp")
        #expect(legendary.damageByPlayer.value == 0.25)
        #expect(DifficultyDamage.destructionExperience(
            10, level: .legendary, multipliers: legendary
        ) == 5)
        #expect(DifficultyDamage.destructionExperience(
            10, level: .adept, multipliers: legendary
        ) == 10, "unchanged at and below Adept")
    }

    /// A synthetic GMST record built in code, never an extracted one.
    private static func setting(_ editorID: String, value: Float, formID: UInt32) -> Data {
        var raw = value.bitPattern.littleEndian
        let data = withUnsafeBytes(of: &raw) { Data($0) }
        let fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
            + ESMFixture.field("DATA", data)
        return ESMFixture.record("GMST", formID: formID, data: fields)
    }
}
