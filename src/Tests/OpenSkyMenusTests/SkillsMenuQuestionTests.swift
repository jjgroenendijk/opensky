// The skills menu asks its questions through an engine message box, and the box's
// answer spends the pick.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import Testing

@MainActor
private final class QuestionWorld: SkillsMenuWorld, SkillsMenuSource {
    var renderer: (any RendererPort)?
    var viewCamera: FreeFlyCamera?
    var uiScene = UIScene.empty
    var menuInputConsumer: (any MenuInputConsumer)?
    var perkSkySource: PerkSkySource?
    var perkSkySettings = PerkSkySettings()
    struct Box {
        let text: String
        let buttons: [String]
        let answer: (Int) -> Void
    }

    var asked: [Box] = []
    var chosen: [ActorValueKind] = []
    var picks = 1

    var skillsMenuSource: (any SkillsMenuSource)? {
        self
    }

    func playLevelUpMusic() {}

    func askSkillsMenuQuestion(
        _ text: String, buttons: [String], answer: @escaping (Int) -> Void
    ) {
        asked.append(Box(text: text, buttons: buttons, answer: answer))
    }

    func skillsMenuWillOpen() {}

    var skillsMenuPlayer: SkillsMenuPlayer {
        SkillsMenuModelTests.player(picks: picks)
    }

    var skillsMenuSkills: [SkillsMenuSkill] {
        SkillsMenuModelTests.allSkills
    }

    func skillsMenuPerks(forSkill _: Int32) -> [SkillsMenuPerk] {
        []
    }

    func skillsMenuChooseAttribute(_ kind: ActorValueKind) -> SkillsMenuOutcome {
        chosen.append(kind)
        picks = 0
        return .done("chose")
    }

    func skillsMenuBuyPerk(node _: UInt32, forSkill _: Int32) -> SkillsMenuOutcome {
        .done("bought")
    }

    func skillsMenuMakeLegendary(_: Int32) -> SkillsMenuOutcome {
        .done("legendary")
    }
}

@MainActor
struct SkillsMenuQuestionTests {
    @Test func theLevelUpPickAsksInAMessageBoxAndSpendsOnOk() throws {
        let world = QuestionWorld()
        let menu = SkillsMenuCoordinator(menuMode: MenuModeController(), world: world)
        menu.model = SkillsMenuModel(
            player: world.skillsMenuPlayer, skills: world.skillsMenuSkills
        )
        menu.route(.button(.accept))
        menu.route(.move(.left))
        #expect(world.asked.count == 1, "one box per question")
        let box = try #require(world.asked.first)
        #expect(box.text == "Increase Health?")
        #expect(box.buttons == ["Ok", "Cancel"])
        #expect(world.chosen.isEmpty)
        box.answer(0)
        #expect(world.chosen == [.health])
        #expect(menu.model?.question == nil)
        #expect(!menu.questionAsked)
    }
}
