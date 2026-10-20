// The World > Progression panel's snapshot and actions. Each action is the
// runtime's own call; the tree reads are in `ProgressionCoordinator+Tree.swift`.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

extension ProgressionCoordinator {
    public var snapshot: ProgressionControlSnapshot {
        guard let leveling, let skills else { return .unavailable }
        let state = leveling.state
        // Built first: it fills the count cache that `perkTreeCache` describes.
        let skillReadouts = skillReadouts(runtime: skills)
        return ProgressionControlSnapshot(
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
            perkTreeCache: treeCounts.readout,
            selectedSkill: skillSelection,
            treeNodes: perkTreeNodes(forSkill: skillSelection),
            selectedNode: nodeSelection,
            perk: perkInspection(node: nodeSelection, forSkill: skillSelection),
            lastActionText: lastActionText,
            experienceRate: perks.skillUseMultiplier(
                SkillUsageConditionResolution(skill: skillSelection)
            )
        )
    }

    // MARK: - Skills

    @discardableResult
    public func advanceSelectedSkill(byUse amount: Float) -> ProgressionActionOutcome {
        applyToSelectedSkill(verb: "took no use") { advanceSkill($0, byUse: amount) }
    }

    @discardableResult
    public func incrementSelectedSkill() -> ProgressionActionOutcome {
        applyToSelectedSkill(verb: "took no point") { incrementSkill($0) }
    }

    // MARK: - Character level

    @discardableResult
    public func awardCharacterExperience(_ amount: Float) -> ProgressionActionOutcome {
        guard let leveling else { return .unavailable }
        let report = leveling.award(characterExperience: amount)
        reportLevel(report)
        return record(.experienceAwarded(
            amount, report, nextLevelAt: leveling.experienceForNextLevel
        ))
    }

    /// What opening the skills menu does to the level, for the panel.
    @discardableResult
    public func applyBankedLevels() -> ProgressionActionOutcome {
        guard let report = applyEarnedLevels() else { return .unavailable }
        return record(.levelsApplied(report))
    }

    @discardableResult
    public func chooseAttributePick(_ kind: ActorValueKind) -> ProgressionActionOutcome {
        switch chooseAttribute(kind) {
        case let .success(state):
            record(.attributeChosen(kind, picksOwed: state.pendingAttributePicks))
        case let .failure(error):
            record(.progressRefused(error))
        }
    }

    @discardableResult
    public func changePerkPoints(by delta: Int) -> ProgressionActionOutcome {
        guard let points = modifyPerkPoints(by: delta) else { return .unavailable }
        return record(.perkPointsChanged(delta: delta, unspent: points))
    }

    // MARK: - Perks

    @discardableResult
    public func spendPointOnSelectedPerk() -> ProgressionActionOutcome {
        guard leveling != nil else { return .unavailable }
        guard let key = selectedPerkKey() else { return record(.noPerk) }
        return switch spendPerkPoint(on: key) {
        case let .success(state):
            record(.perkPointSpent(perk: perkName(key), left: state.perkPoints))
        case let .failure(error):
            record(.progressRefused(error))
        }
    }

    @discardableResult
    public func grantSelectedPerk() -> ProgressionActionOutcome {
        changeSelectedPerk(granting: true)
    }

    @discardableResult
    public func revokeSelectedPerk() -> ProgressionActionOutcome {
        changeSelectedPerk(granting: false)
    }

    @discardableResult
    public func makeSelectedSkillLegendary() -> ProgressionActionOutcome {
        if case let .failure(refusal) = makeSkillLegendary(skillSelection) {
            record(.treeRefused(refusal))
        }
        return lastAction
    }

    @discardableResult
    public func resetSelectedPerkTree() -> ProgressionActionOutcome {
        if case let .failure(refusal) = resetPerkTree(skillSelection) {
            record(.treeRefused(refusal))
        }
        return lastAction
    }

    /// The readout line of `lastAction`, with the load order's training notices.
    public var lastActionText: String {
        lastAction.text(training: training)
    }

    @discardableResult
    func record(_ outcome: ProgressionActionOutcome) -> ProgressionActionOutcome {
        lastAction = outcome
        return outcome
    }

    // MARK: - Private

    private func perkName(_ key: ReferenceKey) -> String {
        perks.runtime?.record(key)?.displayName ?? key.description
    }

    private func applyToSelectedSkill(
        verb: String, _ change: (Int32) -> Bool
    ) -> ProgressionActionOutcome {
        guard skills != nil else { return .unavailable }
        let index = skillSelection
        let name = skillName(index)
        guard change(index), let report = lastAdvance else {
            return record(.skillUnchanged(skill: name, verb: verb))
        }
        return record(.skillAdvanced(report, skill: name))
    }

    private func changeSelectedPerk(granting: Bool) -> ProgressionActionOutcome {
        guard perks.runtime != nil else { return .unavailable }
        guard let key = selectedPerkKey() else { return record(.noPerk) }
        let changed = granting ? perks.add(key, to: .player) : perks.remove(key, from: .player)
        return record(.perkChanged(perk: perkName(key), granted: granting, changed: changed))
    }
}
