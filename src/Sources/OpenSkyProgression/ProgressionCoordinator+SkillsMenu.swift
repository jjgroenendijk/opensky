// The skills menu's reads and spends, answered from the same runtimes the readout uses.
// Names and descriptions resolve through the string tables when the app gave them.
// See docs/engine/skills-menu.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyProgressionInterface

extension ProgressionCoordinator: SkillsMenuSource {
    public func skillsMenuWillOpen() {
        applyEarnedLevels()
    }

    public var skillsMenuPlayer: SkillsMenuPlayer {
        guard let leveling else { return .empty }
        let state = leveling.state
        let identity = world.playerIdentity()
        let needed = leveling.experienceForNextLevel
        return SkillsMenuPlayer(
            name: identity.name,
            race: identity.race,
            level: state.level,
            levelProgress: needed > 0 ? min(1, max(0, state.experience / needed)) : 0,
            health: SkillsMenuPlayer.Meter(.health, of: leveling.values),
            magicka: SkillsMenuPlayer.Meter(.magicka, of: leveling.values),
            stamina: SkillsMenuPlayer.Meter(.stamina, of: leveling.values),
            perkPoints: beastTree.map { Int(world.globalValue(editorID: $0.perkPointsGlobal) ?? 0) }
                ?? state.perkPoints,
            pendingAttributePicks: state.pendingAttributePicks
        )
    }

    public var skillsMenuSkills: [SkillsMenuSkill] {
        guard let skills else { return [] }
        let state = leveling?.state ?? PlayerProgressState()
        return ActorValueIdentity.skillIndices.map { index in
            let threshold = skills.threshold(forSkill: index, on: .player)
            let experience = skills.experience(forSkill: index, on: .player)
            return SkillsMenuSkill(
                index: index,
                name: treeReader.displaySkillName(index),
                description: treeReader.skillDescription(index),
                level: skills.values.value(at: index, on: .player) ?? 0,
                progress: threshold > 0 ? min(1, max(0, experience / threshold)) : 0,
                legendaryCount: state.legendaryCount(ofSkill: index),
                canMakeLegendary: legendaryRefusal(forSkill: index) == nil
            )
        }
    }

    public func skillsMenuPerks(forSkill index: Int32) -> [SkillsMenuPerk] {
        treeReader.skillsMenuPerks(forSkill: index)
    }

    public func skillsMenuChooseAttribute(_ kind: ActorValueKind) -> SkillsMenuOutcome {
        switch chooseAttribute(kind) {
        case .success:
            let name = ActorValueIdentity.name(at: ActorValueIdentity.index(of: kind))
            return .done("\(name ?? "Attribute") increased.")
        case let .failure(error): return .refused(String(describing: error))
        }
    }

    public func skillsMenuBuyPerk(node: UInt32, forSkill index: Int32) -> SkillsMenuOutcome {
        if let tree = BeastPerkTree(actorValueIndex: index) {
            return buyBeastPerk(node: node, in: tree)
        }
        guard
            let head = treeReader.perkKey(node: node, forSkill: index),
            let next = treeReader.nextRank(of: head)
        else {
            return .refused("Every rank is owned.")
        }
        switch spendPerkPoint(on: next) {
        case .success:
            treeReader.invalidateCounts()
            return .done("Perk added.")
        case let .failure(.perkRefused(refusal)):
            return .refused(refusal.readoutText)
        case let .failure(error): return .refused(String(describing: error))
        }
    }

    public func skillsMenuMakeLegendary(_ index: Int32) -> SkillsMenuOutcome {
        switch makeSkillLegendary(index) {
        case let .success(report):
            .done(
                "\(treeReader.displaySkillName(index)) is legendary. "
                    + "\(report.refundedPoints) perk point(s) refunded."
            )
        case let .failure(refusal): .refused(String(describing: refusal))
        }
    }
}

@MainActor
extension SkillsMenuPlayer.Meter {
    init(_ kind: ActorValueKind, of values: any ActorValueAccess) {
        self.init(
            current: values.current(of: .player)[kind],
            maximum: values.maximums(of: .player)[kind]
        )
    }
}
