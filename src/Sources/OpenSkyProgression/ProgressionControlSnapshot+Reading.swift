// The progression readout's one observation of the progression runtimes.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

@MainActor
extension ProgressionControlSnapshot {
    init(
        reading reader: ProgressionTreeReader,
        runtimes: (leveling: PlayerLevelRuntime, skills: SkillAdvancementRuntime)?,
        selection: (skill: Int32, node: UInt32),
        lastActionText: String
    ) {
        guard let (leveling, skills) = runtimes else {
            self = .unavailable
            return
        }
        let state = leveling.state
        let skill = selection.skill
        let perks = reader.perks
        // Built first: it fills the count cache that `perkTreeCache` describes.
        let skillReadouts = reader.skillReadouts(runtime: skills, progress: state)
        self.init(
            isAvailable: true,
            level: state.level,
            experience: state.experience,
            experienceForNextLevel: leveling.experienceForNextLevel,
            perkPoints: state.perkPoints,
            pendingAttributePicks: state.pendingAttributePicks,
            attributePicks: state.attributePicks,
            skillIncreases: state.skillIncreases,
            ownedPerkCount: perks.runtime?.state(of: .player).owned.count ?? 0,
            skills: skillReadouts,
            perkTreeCache: reader.countsReadout,
            selectedSkill: skill,
            treeNodes: reader.perkTreeNodes(forSkill: skill),
            selectedNode: selection.node,
            perk: reader.perkInspection(node: selection.node, forSkill: skill),
            lastActionText: lastActionText,
            experienceRate: perks.skillUseMultiplier(SkillUsageConditionResolution(skill: skill))
        )
    }
}
