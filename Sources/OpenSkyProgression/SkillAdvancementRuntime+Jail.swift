// Jail time costs skill progress. UESP "Skyrim:Crime", Serving Your Sentence: the
// longer the sentence, the more skills lose their progress, and the longest
// sentence clears every skill. Which skills go first is not documented; OpenSky
// takes the ones nearest their next level. See docs/engine/jail.md.

import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

extension SkillAdvancementRuntime {
    /// How many skills a sentence of `days` out of `maximumDays` clears.
    nonisolated public static func jailSkillCount(days: Int, maximumDays: Int) -> Int {
        let skills = Int(ActorValueIdentity.lastSkillIndex - ActorValueIdentity.firstSkillIndex) + 1
        guard days > 0 else { return 0 }
        let share = Double(min(days, max(1, maximumDays))) / Double(max(1, maximumDays))
        return min(skills, Int((Double(skills) * share).rounded(.up)))
    }

    /// Clears the progress of the `count` skills nearest their next level.
    /// - Returns: the skills that lost progress, nearest first.
    @discardableResult
    public func clearProgress(ofSkills count: Int, on holder: ActorValueHolder) -> [Int32] {
        let skills = ActorValueIdentity.firstSkillIndex ... ActorValueIdentity.lastSkillIndex
        var shares: [(skill: Int32, share: Float)] = []
        for skill in skills {
            let share = progressShare(ofSkill: skill, on: holder)
            if share > 0 {
                shares.append((skill, share))
            }
        }
        shares.sort { left, right in
            left.share != right.share ? left.share > right.share : left.skill < right.skill
        }
        let ranked = shares.prefix(max(0, count)).map(\.skill)
        for skill in ranked {
            guard let slot = ActorValueIdentity.skillAdvanceIndex(forSkill: skill) else { continue }
            values.setBase(at: slot, to: 0, on: holder)
        }
        return ranked
    }

    private func progressShare(ofSkill skill: Int32, on holder: ActorValueHolder) -> Float {
        let experience = experience(forSkill: skill, on: holder)
        let threshold = threshold(forSkill: skill, on: holder)
        return threshold > 0 ? experience / threshold : experience
    }
}
