// The level-up and stats movie bridges over a synthetic runtime: the arrays and
// callbacks the engine sends, and the buttons the movie presses.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyProgressionInterface
import Testing

@MainActor
private final class ChoiceLog {
    var choices: [ActorValueKind] = []
}

@MainActor
struct SkillsMenuMovieBridgeTests {
    @Test func theLevelUpButtonsBecomeChoices() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        let log = ChoiceLog()
        LevelUpMenuMovieBridge.prepare(runtime: runtime) { log.choices.append($0) }
        runtime.callHost("addMagicka", arguments: [])
        runtime.callHost("PlaySound", arguments: [.string("UIMenuOK")])
        runtime.callHost("addStamina", arguments: [])
        #expect(log.choices == [.magicka, .stamina])
        #expect(!LevelUpMenuMovieBridge.buttonsBuilt(runtime: runtime))
    }

    @Test func publishFillsTheRingAndTheTreeNames() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        let menuClass = runtime.runtime.makeObject()
        runtime.runtime.globalObject.assign(.object(menuClass), for: StatsMenuMovieBridge.className)
        var sent: [String: [AS2Value]] = [:]
        for name in [
            "SetPlayerInfo",
            "UpdateSkillList",
            "SetDirection",
            "SetStatsMode",
            "SetDescriptionCard"
        ] {
            AS2Natives.method(runtime.runtime, on: runtime.root.object, name: name) { context in
                sent[name] = context.arguments
                return .undefined
            }
        }
        var model = SkillsMenuModel(
            player: SkillsMenuModelTests.player(points: 2), skills: SkillsMenuModelTests.allSkills
        )
        _ = model.handle(.move(.right))
        _ = model.handle(.move(.up))
        model.setPerks([SkillsMenuModelTests.perk(1, x: 2, y: 0)])

        StatsMenuMovieBridge.publish(model, runtime: runtime)

        let ring = try #require(menuClass.lookup("SkillStatsA")?.property.value.objectValue)
        #expect(Self.count(ring) == 18 * StatsMenuMovieBridge.skillStride)
        #expect(ring.lookup("1")?.property.value == .string("Skill 21"))
        let names = try #require(menuClass.lookup("PerkNamesA")?.property.value.objectValue)
        #expect(Self.count(names) == 3)
        #expect(sent["SetDirection"] == [.number(20)])
        #expect(sent["SetStatsMode"] == [.boolean(true), .integer(2)])
        #expect(sent["SetDescriptionCard"]?.first == .boolean(true))
        #expect(sent["SetDescriptionCard"]?[1] == .string("Perk 1"))
        #expect(sent["SetPlayerInfo"]?.count == 13)
        #expect(sent["UpdateSkillList"] == [.boolean(true)])
    }

    private static func count(_ array: AS2Object) -> Int {
        array.ownPropertyNames.count { Int($0) != nil }
    }

    @Test func perkNamesAreEscapedAndTheSelectedOneIsBold() {
        let perk = SkillsMenuModelTests.perk(1, x: 2, y: 0)
        var model = SkillsMenuModel(player: SkillsMenuModelTests.player(), skills: [])
        model.setPerks([perk])
        let values = StatsMenuMovieBridge.perkValues(perk, model: model)
        #expect(values[0] == .string("<b><font color='#8C8C8C'>Perk 1</font></b>"))
        #expect(StatsMenuMovieBridge.escaped("A<B&C") == "A&lt;B&amp;C")
    }
}
