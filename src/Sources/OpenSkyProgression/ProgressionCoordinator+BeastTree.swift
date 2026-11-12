// In a beast form, the skills key opens the form's own perk tree (UESP
// "Skyrim:Lycanthropy" and "Skyrim:Vampire Lord", Skill Perks). Its points are the
// change script's global, not the level's perk points. See docs/engine/beast-forms.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyProgressionInterface

extension ProgressionCoordinator {
    /// The tree of the player's form, when the load order carries it (Dawnguard).
    var beastTree: BeastPerkTree? {
        guard
            let tree = world.playerBeastTree(),
            treeReader.hasPerkTree(tree.actorValueIndex)
        else { return nil }
        return tree
    }

    public var skillsMenuBeastTree: SkillsMenuSkill? {
        guard let tree = beastTree else { return nil }
        let progress = world.globalValue(editorID: tree.progressGlobal) ?? 0
        let next = world.globalValue(editorID: tree.nextPerkGlobal) ?? 0
        return SkillsMenuSkill(
            index: tree.actorValueIndex,
            name: treeReader.displaySkillName(tree.actorValueIndex),
            description: "",
            level: world.globalValue(editorID: tree.perkPointsGlobal) ?? 0,
            progress: next > 0 ? min(1, max(0, progress / next)) : 0,
            legendaryCount: 0,
            canMakeLegendary: false
        )
    }

    /// Spends one of the tree's own points, after the same tree checks a skill perk has.
    func buyBeastPerk(node: UInt32, in tree: BeastPerkTree) -> SkillsMenuOutcome {
        let points = world.globalValue(editorID: tree.perkPointsGlobal) ?? 0
        guard points >= 1 else { return .refused("No perk points.") }
        guard
            let head = treeReader.perkKey(node: node, forSkill: tree.actorValueIndex),
            let next = treeReader.nextRank(of: head)
        else { return .refused("Every rank is owned.") }
        if let refusal = treeReader.perkSpendRefusal(for: next) {
            return .refused(refusal.readoutText)
        }
        guard perks.add(next, to: .player) else { return .refused("Every rank is owned.") }
        world.setGlobalValue(points - 1, editorID: tree.perkPointsGlobal)
        treeReader.invalidateCounts()
        return .done("Perk added.")
    }
}
