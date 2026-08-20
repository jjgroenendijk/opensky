// `ProgressionControlProviding` conformance (issue #500, roadmap item 20.7):
// the live readouts and dev controls the `World > Progression` panel is written
// against.
//
// Every action below goes through the same call the runtime makes — a granted
// use is `SkillAdvancementRuntime.advance`, a spent point is
// `spendPerkPoint(on:)`, a pick is `PlayerLevelRuntime.chooseAttribute` — so
// the panel verifies items 20.4 through 20.6 rather than a second
// implementation of them. Nothing here invents a number.
//
// The reading half lives in `GameViewControllerProgressionTree.swift`.

import Foundation

extension GameViewController: ProgressionControlProviding {
    var progressionSkillSelection: Int32 {
        get { progression.skillSelection }
        set {
            guard ActorValueIdentity.isSkill(index: newValue) else { return }
            guard newValue != progression.skillSelection else { return }
            progression.skillSelection = newValue
            // The old box identity means nothing in the new tree, so the
            // selection lands on the new tree's first box rather than on a
            // number that happens to exist in both.
            progression.nodeSelection = progressionFirstNode(forSkill: newValue)
        }
    }

    var progressionNodeSelection: UInt32 {
        get { progression.nodeSelection }
        set { progression.nodeSelection = newValue }
    }

    var progressionControlSnapshot: ProgressionControlSnapshot {
        guard let leveling = progression.runtime, let advancement = skills.runtime else {
            return .unavailable
        }
        let state = leveling.state
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
            skills: progressionSkillReadouts(runtime: advancement),
            selectedSkill: progression.skillSelection,
            treeNodes: progressionPerkTreeNodes(forSkill: progression.skillSelection),
            selectedNode: progression.nodeSelection,
            perk: progressionPerkInspection(
                node: progression.nodeSelection, forSkill: progression.skillSelection
            ),
            lastActionText: progression.lastActionText
        )
    }

    // MARK: - Skills

    @discardableResult
    func advanceSelectedSkill(byUse amount: Float) -> String {
        advance(.advance, magnitude: amount, verb: "took no use")
    }

    @discardableResult
    func incrementSelectedSkill() -> String {
        advance(.increment, magnitude: 1, verb: "took no point")
    }

    // MARK: - Character level

    @discardableResult
    func awardCharacterExperience(_ amount: Float) -> String {
        guard let runtime = progression.runtime else { return Self.noProgressionText }
        let report = runtime.award(characterExperience: amount)
        progression.lastActionText = report.didLevel
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
                runtime.experienceForNextLevel
            )
        return progression.lastActionText
    }

    @discardableResult
    func chooseAttributePick(_ kind: ActorValueKind) -> String {
        switch choosePlayerAttribute(kind) {
        case let .success(state):
            progression.lastActionText = String(
                format: "Chose %@: %d pick(s) still owed.",
                kind.rawValue,
                state.pendingAttributePicks
            )
        case let .failure(error):
            progression.lastActionText = Self.text(for: error)
        }
        return progression.lastActionText
    }

    @discardableResult
    func changePerkPoints(by delta: Int) -> String {
        guard let points = modifyPlayerPerkPoints(by: delta) else {
            return Self.noProgressionText
        }
        progression.lastActionText =
            "Changed perk points by \(delta): \(points) unspent."
        return progression.lastActionText
    }

    // MARK: - Perks

    @discardableResult
    func spendPointOnSelectedPerk() -> String {
        guard progression.runtime != nil else { return Self.noProgressionText }
        guard let key = progressionSelectedPerkKey() else {
            progression.lastActionText = Self.noPerkText
            return progression.lastActionText
        }
        switch spendPerkPoint(on: key) {
        case let .success(state):
            progression.lastActionText =
                "Spent a point on \(perkName(key)): \(state.perkPoints) left."
        case let .failure(error):
            progression.lastActionText = Self.text(for: error)
        }
        return progression.lastActionText
    }

    @discardableResult
    func grantSelectedPerk() -> String {
        changeSelectedPerk(granting: true)
    }

    @discardableResult
    func revokeSelectedPerk() -> String {
        changeSelectedPerk(granting: false)
    }

    // MARK: - Private

    private static let noProgressionText =
        "Progression unavailable: no game data loaded."
    private static let noPerkText = "This box grants no perk."

    /// Why a pick or a spend was refused, spelled as the rule that refused it.
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

    private func advance(
        _ kind: PapyrusSkillAdvance,
        magnitude: Float,
        verb: String
    ) -> String {
        guard skills.runtime != nil else { return Self.noProgressionText }
        let index = progression.skillSelection
        let name = progressionSkillName(index)
        guard
            advancePlayerSkill(kind, at: index, by: magnitude),
            let report = skills.lastAdvance
        else {
            progression.lastActionText = "\(name) \(verb):"
                + " this load order carries no advancement parameters for it."
            return progression.lastActionText
        }
        progression.lastActionText = ProgressionControlReadout.advanceText(
            report, skillName: name
        )
        return progression.lastActionText
    }

    private func changeSelectedPerk(granting: Bool) -> String {
        guard perks.runtime != nil else { return Self.noProgressionText }
        guard let key = progressionSelectedPerkKey() else {
            progression.lastActionText = Self.noPerkText
            return progression.lastActionText
        }
        let changed = granting
            ? addPerk(key, to: .player)
            : removePerk(key, from: .player)
        let name = perkName(key)
        progression.lastActionText = switch (granting, changed) {
        case (true, true): "Granted \(name)."
        case (true, false): "\(name) was already owned."
        case (false, true): "Removed \(name)."
        case (false, false): "\(name) was not owned."
        }
        return progression.lastActionText
    }
}
