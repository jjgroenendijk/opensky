// Progression readout lines (issue #500, roadmap item 20.7), formatted in the
// engine target rather than in the panel section for the reason
// `ActorValueControlReadout` is: a string a milestone gate asserts on belongs
// where a unit test can reach it without a window.
//
// Documented in docs/engine/character-leveling.md.

import Foundation

nonisolated enum ProgressionControlReadout {
    /// Column width the skill lines pad their names to. Wide enough for
    /// "Enchanting"; a longer modded name pushes its own line out rather than
    /// being truncated, because a cut-off name is worse than a ragged column.
    private static let skillNameWidth = 14

    /// The character line: what the player is, what the next level costs, and
    /// what is waiting to be spent.
    static func characterText(for snapshot: ProgressionControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Character: unavailable" }
        return String(
            format: "Character: level %d — %.0f/%.0f XP  %d perk point(s)"
                + "  %d attribute pick(s) owed",
            snapshot.level,
            snapshot.experience,
            snapshot.experienceForNextLevel,
            snapshot.perkPoints,
            snapshot.pendingAttributePicks
        )
    }

    /// What the level-ups already accepted bought, which is the history a
    /// level-up screen lists rather than the mechanism: the ten points a pick
    /// grants live in the actor value's base offset.
    static func picksText(for snapshot: ProgressionControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Picks: unavailable" }
        let counts = ActorValueKind.allCases.map { kind in
            "\(kind.shortLabel) \(snapshot.attributePicks.count { $0 == kind })"
        }.joined(separator: "  ")
        return "Picks: \(counts)"
            + "  — \(snapshot.skillIncreases) skill point(s) this session"
            + ", \(snapshot.ownedPerkCount) perk(s) owned"
    }

    /// The eighteen skills, one line each: what the skill reads, what it was
    /// trained to, and how far the next point is, closed by what the per-skill
    /// count cache behind those numbers is doing (issue #556) — the reading that
    /// makes the reuse visible from the panel rather than from a profiler.
    static func skillsText(for snapshot: ProgressionControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Skills: unavailable" }
        guard !snapshot.skills.isEmpty else {
            return "Skills: this load order carries no AVIF skill records."
        }
        let lines = snapshot.skills.map { skill in
            let marker = skill.index == snapshot.selectedSkill ? ">" : " "
            let name = skill.name.count >= Self.skillNameWidth
                ? skill.name
                : skill.name.padding(
                    toLength: Self.skillNameWidth, withPad: " ", startingAt: 0
                )
            return String(
                format: "%@ %@ %5.1f (base %5.1f)  %6.1f/%6.1f XP  perks %d/%d",
                marker,
                name,
                skill.current,
                skill.base,
                skill.experience,
                skill.threshold,
                skill.ownedPerks,
                skill.treePerks
            )
        }
        return (["Skills (\(snapshot.skills.count)):"] + lines
            + [snapshot.perkTreeCache.describedLine]).joined(separator: "\n")
    }

    /// The selected skill's tree, one line per box, in `INAM` order. A list
    /// rather than a drawn grid: the connections are what the tree means, and
    /// they read exactly as well spelled out.
    static func perkTreeText(for snapshot: ProgressionControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Perk tree: unavailable" }
        let skillName = snapshot.selectedSkillReadout?.name
            ?? ActorValueIdentity.description(of: snapshot.selectedSkill)
        guard !snapshot.treeNodes.isEmpty else {
            return "Perk tree: \(skillName) has no tree in this load order."
        }
        let lines = snapshot.treeNodes.map { node in
            let marker = node.node == snapshot.selectedNode ? ">" : " "
            let connections = node.connections.map(String.init).joined(separator: ", ")
            return "\(marker) #\(node.node) \(node.name)"
                + rankText(node)
                + " — \(availabilityText(node))"
                + ", parent \(node.requiresParent ? "required" : "optional")"
                + ", lines to [\(connections)]"
        }
        return (["Perk tree: \(skillName) (\(snapshot.treeNodes.count) nodes):"] + lines)
            .joined(separator: "\n")
    }

    /// The selected box's record: its flags, its own conditions, and one line
    /// per effect.
    static func perkText(for snapshot: ProgressionControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Selected perk: unavailable" }
        guard let perk = snapshot.perk else {
            return "Selected perk: none — this box grants no perk."
        }
        var lines = [
            "Selected perk: \(perk.name) [\(perk.editorID)] \(perk.formID)"
                + " — \(perk.isOwned ? "owned" : "not owned")"
                + ", \(perk.isPlayable ? "playable" : "not playable")"
                + (perk.isTrait ? ", trait" : "")
                + (perk.isHidden ? ", hidden" : "")
        ]
        if perk.conditions.isEmpty {
            lines.append("  conditions: none")
        } else {
            lines.append("  conditions (\(perk.conditions.count)):")
            lines.append(contentsOf: perk.conditions.map { "    \($0)" })
        }
        if perk.effects.isEmpty {
            lines.append("  effects: none")
        } else {
            lines.append("  effects (\(perk.effects.count)):")
            lines.append(contentsOf: perk.effects.map { "    \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    /// What one granted use or point did, which is what the panel prints as
    /// its last-action line: the experience it was worth, the level it moved,
    /// and the character level it bought.
    static func advanceText(_ report: SkillAdvanceReport, skillName: String) -> String {
        var text = String(
            format: "%@: +%.1f XP, %.0f banked",
            skillName,
            report.experience,
            report.carriedExperience
        )
        if report.didAdvance {
            text += String(
                format: ", level %.0f to %.0f, +%.0f character XP",
                report.previousLevel,
                report.level,
                report.characterExperience
            )
        }
        if let levelUp = report.levelUp, levelUp.didLevel {
            text += ", character level \(levelUp.previousLevel) to \(levelUp.level)"
        }
        return text + "."
    }

    /// Which skill and box the controls act on, and what the last one did.
    static func controlsText(for snapshot: ProgressionControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Controls: unavailable" }
        let skillName = snapshot.selectedSkillReadout?.name
            ?? ActorValueIdentity.description(of: snapshot.selectedSkill)
        return "Controls: \(skillName), box #\(snapshot.selectedNode)"
            + "\n\(snapshot.lastActionText)"
    }

    /// Why a box cannot be bought right now, spelled as the rule that refused
    /// it — every one of these is something a level-up screen has to say out
    /// loud rather than a greyed-out button with no reason.
    static func availabilityText(_ node: PerkTreeNodeReadout) -> String {
        // A box granting nothing is not "available": it is the tree's entry
        // node, or a dangling `PNAM`. No point is ever spent on either.
        guard !node.grantsNoPerk else { return "grants no perk" }
        guard let refusal = node.refusal else { return "available" }
        return description(of: refusal)
    }

    static func description(of refusal: PerkSpendRefusal) -> String {
        switch refusal {
        case .unresolvedPerk: "no PERK record in this load order"
        case .notPlayable: "not playable"
        case .alreadyOwned: "owned"
        case .notInPerkTree: "in no perk tree"
        case let .previousRankMissing(perk): "needs the rank below (\(perk))"
        case .parentMissing: "needs an owned parent"
        case .unmetCondition: "its own conditions do not hold"
        }
    }

    /// A box's place in its `NNAM` rank chain, printed only for a chain longer
    /// than one record: "rank 0 of 1" on every single-rank perk would be noise
    /// on most of a tree.
    private static func rankText(_ node: PerkTreeNodeReadout) -> String {
        guard node.rankCount > 1 else { return "" }
        return " (rank \(node.ownedRank)/\(node.rankCount))"
    }
}
