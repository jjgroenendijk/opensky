// The progression snapshot and actions. Each action is the
// runtime's own call; the tree reads are in `ProgressionCoordinator+Tree.swift`.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyProgressionInterface

extension ProgressionCoordinator {
    var snapshot: ProgressionControlSnapshot {
        ProgressionControlSnapshot(
            reading: treeReader,
            runtimes: leveling.flatMap { leveling in skills.map { (leveling, $0) } },
            selection: (skillSelection, nodeSelection),
            lastActionText: lastActionText
        )
    }

    // MARK: - Character level

    @discardableResult
    public func awardCharacterExperience(_ amount: Float) -> ProgressionActionOutcome {
        guard let leveling else { return .unavailable }
        let report = leveling.award(characterExperience: amount)
        notices.reportLevel(report)
        return record(.experienceAwarded(
            amount, report, nextLevelAt: leveling.experienceForNextLevel
        ))
    }

    @discardableResult
    func changePerkPoints(by delta: Int) -> ProgressionActionOutcome {
        guard let points = modifyPerkPoints(by: delta) else { return .unavailable }
        return record(.perkPointsChanged(delta: delta, unspent: points))
    }

    // MARK: - Perks

    @discardableResult
    func spendPointOnSelectedPerk() -> ProgressionActionOutcome {
        guard leveling != nil else { return .unavailable }
        guard let key = treeReader.perkKey(node: nodeSelection, forSkill: skillSelection)
        else { return record(.noPerk) }
        return switch spendPerkPoint(on: key) {
        case let .success(state):
            record(.perkPointSpent(perk: treeReader.perkName(key), left: state.perkPoints))
        case let .failure(error):
            record(.progressRefused(error))
        }
    }

    @discardableResult
    func grantSelectedPerk() -> ProgressionActionOutcome {
        changeSelectedPerk(granting: true)
    }

    @discardableResult
    func revokeSelectedPerk() -> ProgressionActionOutcome {
        changeSelectedPerk(granting: false)
    }

    /// The readout line of `lastAction`, with the load order's training notices.
    var lastActionText: String {
        lastAction.text(training: training)
    }

    @discardableResult
    func record(_ outcome: ProgressionActionOutcome) -> ProgressionActionOutcome {
        lastAction = outcome
        return outcome
    }

    // MARK: - Private

    private func changeSelectedPerk(granting: Bool) -> ProgressionActionOutcome {
        guard perks.runtime != nil else { return .unavailable }
        guard let key = treeReader.perkKey(node: nodeSelection, forSkill: skillSelection)
        else { return record(.noPerk) }
        let changed = granting ? perks.add(key, to: .player) : perks.remove(key, from: .player)
        return record(.perkChanged(
            perk: treeReader.perkName(key),
            granted: granting,
            changed: changed
        ))
    }
}
