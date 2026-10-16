// Typed game-setting reads and the list of settings the game never uses.

import Foundation
import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import Testing

struct GameSettingValuesTests {
    private struct Tuning {
        var speed: Float = 1
        var count = 2
        var enabled = false
    }

    @Test
    func readsLayTheDefinedSettingsOverTheDefaults() throws {
        let store = try GameSettingFixture.store([
            "fSpeed": .float(4.5), "iCount": .integer(7), "bEnabled": .boolean(true)
        ])
        var tuning = Tuning()
        store.read("fSpeed", into: &tuning, \.speed)
        store.read("iCount", into: &tuning, \.count)
        store.read("bEnabled", into: &tuning, \.enabled)
        #expect(tuning.speed == 4.5)
        #expect(tuning.count == 7)
        #expect(tuning.enabled)
    }

    @Test
    func aMissingOrWronglyTypedSettingKeepsTheDefault() throws {
        let store = try GameSettingFixture.store([
            "fCount": .float(2.5), "fNaN": .float(.nan), "sSpeed": .text("fast")
        ])
        var tuning = Tuning()
        store.read("fCount", into: &tuning, \.count)
        store.read("fNaN", into: &tuning, \.speed)
        store.read("sSpeed", into: &tuning, \.speed)
        store.read("bMissing", into: &tuning, \.enabled)
        #expect(tuning.count == 2)
        #expect(tuning.speed == 1)
        #expect(!tuning.enabled)
    }

    @Test
    func anIntegerSettingReadsAsANumber() throws {
        let store = try GameSettingFixture.store(["iLevel": .integer(12)])
        #expect(store.number("iLevel") == 12)
    }

    @Test
    func aStringSettingNamesItsPlugin() throws {
        let store = try GameSettingFixture.store(["sYes": .text("Yes")])
        #expect(store.text("sYes") == ResolvedGameText(
            text: .inline("Yes"),
            sourcePlugin: "Tuning.esp"
        ))
    }

    @Test
    func unusedSettingsHaveAReasonAndUsedOnesDoNot() {
        #expect(GameSettingsUnused.reason(for: "fVATSPlaybackDelay") == .vats)
        #expect(GameSettingsUnused.reason(for: "SKINECTCANTINIT") == .consoles)
        #expect(GameSettingsUnused.reason(for: "fCombatDistance") == nil)
    }

    @Test func regenerationSettingsComeFromTheLoadOrder() throws {
        let store = try GameSettingFixture.store([
            "fCombatStaminaRegenRateMult": .float(0.5),
            "fDamagedAVRegenDelay": .float(2),
            "fDamagedHealthRegenDelay": .float(0.25),
            "bRegenNPCMagickaDuringCast": .boolean(true)
        ])
        let settings = RegenerationSettings.resolve(store: store)
        #expect(settings.combatStaminaMult == 0.5)
        #expect(settings.healthDelay == 0.25)
        #expect(settings.magickaDelay == 2)
        #expect(settings.npcMagickaDuringCast)
    }

    @Test func staminaCostsComeFromTheLoadOrder() throws {
        let store = try GameSettingFixture.store([
            "fSprintStaminaDrainMult": .float(10),
            "fStaminaBlockBase": .float(5)
        ])
        let settings = StaminaSettings.resolve(store: store)
        #expect(abs(settings.sprintDrain(wornWeight: 50) - 20) < 1e-4)
        #expect(settings.blockCost(incomingDamage: 40) == 15)
        #expect(StaminaSettings.vanilla.sprintDrain(wornWeight: -3) == 7)
    }
}
