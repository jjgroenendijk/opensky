// The skills menu model: the level-up page first while a pick is owed, the ring in
// altar order, tree navigation over the grid, and the legendary question.

import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyProgressionInterface
import Testing

struct SkillsMenuModelTests {
    static func player(picks: Int = 0, points: Int = 1) -> SkillsMenuPlayer {
        let meter = SkillsMenuPlayer.Meter(current: 100, maximum: 100)
        return SkillsMenuPlayer(
            name: "Prisoner", race: "Nord", level: 2, levelProgress: 0.5, health: meter,
            magicka: meter, stamina: meter, perkPoints: points, pendingAttributePicks: picks
        )
    }

    static func skill(_ index: Int32, level: Float = 15) -> SkillsMenuSkill {
        SkillsMenuSkill(
            index: index, name: "Skill \(index)", description: "", level: level,
            progress: 0, legendaryCount: 0, canMakeLegendary: level >= 100
        )
    }

    static func perk(_ node: UInt32, x: Float, y: Float, refusal: String? = nil) -> SkillsMenuPerk {
        SkillsMenuPerk(
            node: node, name: "Perk \(node)", description: "", requirement: "", gridX: x,
            gridY: y, connections: [], ownedRank: 0, rankCount: 1, refusal: refusal
        )
    }

    static let allSkills = (Int32(6) ... 23).map { skill($0) }

    @Test func anOwedPickOpensOnTheLevelUpPage() {
        var model = SkillsMenuModel(player: Self.player(picks: 1), skills: Self.allSkills)
        #expect(model.page == .levelUp)
        #expect(model.selectedAttribute == .health)
        _ = model.handle(.move(.left))
        #expect(model.handle(.button(.accept)) == .chooseAttribute(.magicka))
        model.refresh(player: Self.player(picks: 0), skills: Self.allSkills)
        #expect(model.page == .skills)
    }

    @Test func theRingFollowsTheAltarOrderAndWraps() {
        var model = SkillsMenuModel(player: Self.player(), skills: Self.allSkills)
        #expect(model.skills.map(\.index) == SkillsMenuModel.ringOrder)
        #expect(model.selectedSkill?.index == 21)
        _ = model.handle(.move(.left))
        #expect(model.selectedSkill?.index == 16)
        _ = model.handle(.move(.right))
        _ = model.handle(.move(.right))
        #expect(model.selectedSkill?.index == 19)
    }

    @Test func upEntersTheTreeOnItsLowestBoxAndMovesAlongTheGrid() {
        var model = SkillsMenuModel(player: Self.player(), skills: Self.allSkills)
        #expect(model.handle(.move(.up)) == .showTree(21))
        model.setPerks([
            Self.perk(2, x: 2, y: 1), Self.perk(1, x: 2, y: 0), Self.perk(3, x: 3, y: 1)
        ])
        #expect(model.selectedPerk?.node == 1)
        _ = model.handle(.move(.up))
        #expect(model.selectedPerk?.node == 2)
        _ = model.handle(.move(.right))
        #expect(model.selectedPerk?.node == 3)
        #expect(model.handle(.button(.accept)) == .buyPerk(node: 3, skill: 21))
        _ = model.handle(.move(.down))
        _ = model.handle(.move(.down))
        #expect(model.page == .skills)
    }

    @Test func aRefusedBoxShowsWhyInsteadOfBuying() {
        var model = SkillsMenuModel(player: Self.player(), skills: Self.allSkills)
        _ = model.handle(.button(.accept))
        model.setPerks([Self.perk(1, x: 0, y: 0, refusal: "conditions not met")])
        #expect(model.handle(.button(.accept)) == nil)
        #expect(model.message == "conditions not met")
    }

    @Test func legendaryAsksFirstAndOnlyAtOneHundred() {
        var skills = Self.allSkills
        skills[15] = Self.skill(21, level: 100)
        var model = SkillsMenuModel(player: Self.player(), skills: skills)
        _ = model.handle(.button(.yButton))
        guard case .legendary = model.page else {
            Issue.record("expected the legendary question")
            return
        }
        #expect(model.handle(.button(.accept)) == nil)
        #expect(model.page == .skills)
        _ = model.handle(.button(.yButton))
        _ = model.handle(.move(.up))
        #expect(model.handle(.button(.accept)) == .makeLegendary(21))
        _ = model.handle(.move(.right))
        _ = model.handle(.button(.yButton))
        #expect(model.page == .skills)
        #expect(model.message?.contains("100") == true)
    }

    @Test func cancelLeavesTheTreeThenCloses() {
        var model = SkillsMenuModel(player: Self.player(), skills: Self.allSkills)
        _ = model.handle(.move(.up))
        #expect(model.handle(.button(.cancel)) == nil)
        #expect(model.page == .skills)
        #expect(model.handle(.button(.cancel)) == .close)
    }
}
