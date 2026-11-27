// The parts the menu adapters hand their reads to fall back when no records have loaded.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyMagicInterface
@testable import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkySessionTesting
import Testing

@MainActor
struct MenuAdapterPartsTests {
    private let host = MenuHost()

    @Test func withoutRecordsTheRaceMenuIsEmpty() {
        host.fakeMapWorld.settingTextsResult = GameSettingTexts<GenderText>.vanilla
        let races = MenuWorldAdapter(game: host, now: { Date() }).skillsRace
        #expect(races.playableRaces.isEmpty)
        #expect(races.raceMenuLabels == RaceMenuLabels(texts: [:], genders: .vanilla))
        #expect(races.raceMenuOptions(race: FormID(0x13746), isFemale: false) == .empty)
        #expect(races.racePresets(race: FormID(0x13746), isFemale: true).isEmpty)
        #expect(races.identityRecords == nil)
        #expect(races.recordIdentity == nil)
        #expect(races.titleSettings == .vanilla)
        #expect(MenuWorldAdapter(game: host, now: { Date() }).titleSettings == .vanilla)
    }

    /// The race menu offers every `ACBS` `0x4` NPC of the race and sex, listed ones first.
    @Test func racePresetsAreTheFlaggedNPCsOfTheRaceAndSex() throws {
        let actors = try [
            npc(0x30, flags: 0x4, race: 0xA), npc(0x20, flags: 0x4, race: 0xA),
            npc(0x10, flags: 0x4, race: 0xA), npc(0x40, flags: 0x5, race: 0xA),
            npc(0x50, flags: 0x4, race: 0xB), npc(0x60, flags: 0, race: 0xA),
            npc(0x7, flags: 0x4, race: 0xA)
        ].reduce(into: [UInt32: ActorBase]()) { $0[$1.formID.rawValue] = $1 }
        let presets = RaceMenuReads.presetNPCs(
            race: FormID(0xA), isFemale: false, listed: [FormID(0x30)], actors: actors
        )
        #expect(presets == [FormID(0x30), FormID(0x10), FormID(0x20)])
    }

    @Test func theActivateChoiceQuestionAndTheCompassGoThroughTheirPorts() {
        host.fakeMapWorld.settingTextsResult = GameSettingTexts<ActivationChoiceText>.vanilla
        let perks = PerkActivationWorldAdapter(game: host, stage: nil)
        #expect(perks.activationChoiceMessage == ActivationChoiceText.message.fallback)
        let place = CompassLocation(position: .zero, isKnown: true, opacityPercent: 100)
        MapWorldAdapter(game: host).showCompassLocations([place])
        #expect(host.fakeHud.updateCompassLocationsCalls == [[place]])
    }

    @Test func aPluginTextWithoutStringsHasNoText() {
        let map = MapWorldAdapter(game: host)
        let setting = ResolvedGameText(text: .tableID(7), sourcePlugin: "base.esm")
        #expect(map.text(setting) == nil)
        #expect(map.playerSetMarker == nil)
        let tamriel = ResolvedFormID(plugin: "base.esm", objectID: 0x3C)
        #expect(map.mapMarkerSites(in: tamriel).isEmpty)
    }

    @Test func theMagicTabsCarryEachRowsCardAndTheEffectsTab() {
        let card = MagicMenuSpellCard(kind: .activeEffect(secondsLeft: 5), effects: "Burns")
        let menu = host.fakeMagic.magicMenu
        menu.magicMenuCategoryOrder = ["DESTRUCTION", "SHOUTS"]
        menu.magicMenuSpells = [MagicMenuSpell(
            name: "Flames",
            isReadied: true,
            category: "DESTRUCTION"
        )]
        menu.magicMenuShouts = [MagicMenuSpell(
            name: "Force", isReadied: false, category: "SHOUTS",
            card: MagicMenuSpellCard(kind: .shout(words: []), effects: "Push")
        )]
        var burn = MagicMenuSpell(name: "Burning", isReadied: false, card: card)
        burn.isNegative = true
        menu.magicMenuActiveEffects = [burn]
        menu.magicMenuActiveEffectsTitle = "ACTIVE EFFECTS"
        let tabs = MenuScreensGiftListsAdapter(game: host).magicMenuCategories
        #expect(tabs.map(\.label) == ["All", "DESTRUCTION", "SHOUTS", "ACTIVE EFFECTS"])
        #expect(tabs[2].rows.first?.spellCard?.effects == "Push")
        let effect = tabs[3].rows.first
        #expect(effect?.spellCard == card)
        #expect(effect?.isNegative == true)
        #expect(effect?.tag == 1)
    }
}

private func npc(_ formID: UInt32, flags: UInt32, race: UInt32) throws -> ActorBase {
    var acbs = Data()
    acbs.appendUInt32(flags)
    acbs.append(Data(count: 20))
    var raceID = Data()
    raceID.appendUInt32(race)
    let fields = ESMFixture.field("ACBS", acbs) + ESMFixture.field("RNAM", raceID)
    return try ActorBase(
        record: ESMFixture.parseRecord(ESMFixture.record("NPC_", formID: formID, data: fields)),
        localized: false
    )
}
