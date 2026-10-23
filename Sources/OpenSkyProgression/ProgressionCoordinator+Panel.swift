// The progression snapshot and actions. Each action is the
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

    private func changeSelectedPerk(granting: Bool) -> ProgressionActionOutcome {
        guard perks.runtime != nil else { return .unavailable }
        guard let key = selectedPerkKey() else { return record(.noPerk) }
        let changed = granting ? perks.add(key, to: .player) : perks.remove(key, from: .player)
        return record(.perkChanged(perk: perkName(key), granted: granting, changed: changed))
    }
}
