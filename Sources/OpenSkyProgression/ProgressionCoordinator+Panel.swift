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
            lastActionText: lastActionText
        )
    }

    // MARK: - Skills

    @discardableResult
    public func advanceSelectedSkill(byUse amount: Float) -> String {
        applyToSelectedSkill(verb: "took no use") { advanceSkill($0, byUse: amount) }
    }

    @discardableResult
    public func incrementSelectedSkill() -> String {
        applyToSelectedSkill(verb: "took no point") { incrementSkill($0) }
    }

    // MARK: - Character level

    @discardableResult
    public func awardCharacterExperience(_ amount: Float) -> String {
        guard let leveling else { return Self.noProgressionText }
        let report = leveling.award(characterExperience: amount)
        lastActionText = report.didLevel
            ? String(
                format: "Awarded %.0f character XP: level %d to %d, "
                    + "%d perk point(s), %d pick(s) owed.",
                amount,
                report.previousLevel,
                report.level,
                report.perkPoints,
                report.pendingAttributePicks
            )
            : String(
                format: "Awarded %.0f character XP: still level %d, %.0f/%.0f banked.",
                amount,
                report.level,
                report.carriedExperience,
                leveling.experienceForNextLevel
            )
        return lastActionText
    }

    @discardableResult
    public func chooseAttributePick(_ kind: ActorValueKind) -> String {
        switch chooseAttribute(kind) {
        case let .success(state):
            lastActionText = String(
                format: "Chose %@: %d pick(s) still owed.",
                kind.rawValue,
                state.pendingAttributePicks
            )
        case let .failure(error):
            lastActionText = Self.text(for: error)
        }
        return lastActionText
    }

    @discardableResult
    public func changePerkPoints(by delta: Int) -> String {
        guard let points = modifyPerkPoints(by: delta) else { return Self.noProgressionText }
        lastActionText = "Changed perk points by \(delta): \(points) unspent."
        return lastActionText
    }

    // MARK: - Perks

    @discardableResult
    public func spendPointOnSelectedPerk() -> String {
        guard leveling != nil else { return Self.noProgressionText }
        guard let key = selectedPerkKey() else {
            lastActionText = Self.noPerkText
            return lastActionText
        }
        switch spendPerkPoint(on: key) {
        case let .success(state):
            lastActionText = "Spent a point on \(perkName(key)): \(state.perkPoints) left."
        case let .failure(error):
            lastActionText = Self.text(for: error)
        }
        return lastActionText
    }

    @discardableResult
    public func grantSelectedPerk() -> String {
        changeSelectedPerk(granting: true)
    }

    @discardableResult
    public func revokeSelectedPerk() -> String {
        changeSelectedPerk(granting: false)
    }

    // MARK: - Private

    private static let noProgressionText = "Progression unavailable: no game data loaded."
    private static let noPerkText = "This box grants no perk."

    /// Spelled as the rule that refused.
    private static func text(for error: PlayerProgressError) -> String {
        switch error {
        case .noAttributePickOwed:
            "No attribute pick is owed: gain a level first."
        case .noPerkPoints:
            "No perk points to spend."
        case let .perkRefused(refusal):
            "Refused: \(ProgressionControlReadout.description(of: refusal))."
        }
    }

    private func perkName(_ key: ReferenceKey) -> String {
        perks.runtime?.record(key)?.displayName ?? key.description
    }

    private func applyToSelectedSkill(verb: String, _ change: (Int32) -> Bool) -> String {
        guard skills != nil else { return Self.noProgressionText }
        let index = skillSelection
        let name = skillName(index)
        guard change(index), let report = lastAdvance else {
            lastActionText = "\(name) \(verb):"
                + " this load order carries no advancement parameters for it."
            return lastActionText
        }
        lastActionText = ProgressionControlReadout.advanceText(report, skillName: name)
        return lastActionText
    }

    private func changeSelectedPerk(granting: Bool) -> String {
        guard perks.runtime != nil else { return Self.noProgressionText }
        guard let key = selectedPerkKey() else {
            lastActionText = Self.noPerkText
            return lastActionText
        }
        let changed = granting ? perks.add(key, to: .player) : perks.remove(key, from: .player)
        let name = perkName(key)
        lastActionText = switch (granting, changed) {
        case (true, true): "Granted \(name)."
        case (true, false): "\(name) was already owned."
        case (false, true): "Removed \(name)."
        case (false, false): "\(name) was not owned."
        }
        return lastActionText
    }
}
