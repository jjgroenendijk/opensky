// Combat-loop readout lines (issue #374, roadmap item 15.7), formatted here
// rather than in the panel section for the reason `RagdollReadout`,
// `ArcheryReadout` and `MeleeCombatReadout` are: a string a milestone gate
// asserts on belongs in the engine target, where a unit test can reach it
// without a window.
//
// Documented in docs/engine/combat.md.

import Foundation

nonisolated enum CombatLoopReadout {
    /// Whether the player is fighting, and whom.
    static func stateText(for snapshot: CombatLoopSnapshot) -> String {
        guard snapshot.isAvailable else { return "Combat: unavailable" }
        guard snapshot.isPlayerInCombat else {
            return "Combat: out of combat (\(snapshot.deadCount) dead nearby)"
        }
        return "Combat: in combat with \(snapshot.targetName)"
            + String(format: " at %.0f u", snapshot.targetDistance)
            + " (\(snapshot.hostileCount) hostile, \(snapshot.deadCount) dead)"
    }

    /// The opponent and where its attack clock is.
    static func devTargetText(for snapshot: CombatLoopSnapshot) -> String {
        guard snapshot.isAvailable else { return "Dev target: unavailable" }
        guard snapshot.devTargetIsRunning else {
            return "Dev target: none spawned"
        }
        return "Dev target: \(snapshot.devTargetName), \(snapshot.devTargetPhase.rawValue)"
            + " — \(snapshot.devTargetAttackCount) attacks,"
            + " \(snapshot.devTargetContactCount) contact frames"
    }

    /// What the hostility toggle acts on, and where it stands.
    static func hostilityText(for snapshot: CombatLoopSnapshot) -> String {
        guard snapshot.isAvailable else { return "Hostility: unavailable" }
        let regard = snapshot.selectedActorIsHostile ? "hostile" : "neutral"
        return "Hostility: \(snapshot.selectedActorName) is \(regard)"
    }

    /// Blows the player has taken, newest last.
    static func incomingText(for snapshot: CombatLoopSnapshot) -> String {
        guard snapshot.isAvailable else { return "Hits taken: unavailable" }
        guard snapshot.incomingHitCount > 0 else { return "Hits taken: none" }
        let flash = String(format: "%.2f", snapshot.damageFlash)
        let header = "Hits taken: \(snapshot.incomingHitCount) (flash \(flash))"
        guard !snapshot.incomingTrace.isEmpty else { return header }
        return ([header] + snapshot.incomingTrace.map { "  \($0)" }).joined(separator: "\n")
    }

    /// One incoming hit as a trace line.
    static func traceLine(for hit: CombatIncomingHit) -> String {
        let blocked = hit.damage.wasBlocked
            ? String(format: ", blocked %.0f%%", hit.damage.blockedFraction * 100)
            : ""
        let reaction = hit.playedReaction ? "" : ", no reaction played"
        return "attack \(hit.attackID) from \(hit.aggressor)"
            + String(format: ": %.1f damage", hit.damage.applied)
            + blocked + reaction
    }

    /// Live transients against their ceilings, and what the caps have removed.
    static func transientText(for snapshot: CombatLoopSnapshot) -> String {
        guard snapshot.isAvailable else { return "Transients: unavailable" }
        let live = snapshot.transients
        let caps = snapshot.limits
        let trimmed = snapshot.trimmedTransients
        let populations = [
            "arrows in flight \(live.liveProjectiles)/\(caps.liveProjectiles)",
            "stuck \(live.stuckProjectiles)/\(caps.stuckProjectiles)",
            "ragdolls \(live.activeRagdolls)/\(caps.activeRagdolls)",
            "awake bodies \(live.awakeBodies)/\(caps.awakeBodies)"
        ].joined(separator: ", ")
        let removed = trimmed == .none
            ? "nothing trimmed"
            : "trimmed \(trimmed.liveProjectiles)/\(trimmed.stuckProjectiles)"
            + "/\(trimmed.activeRagdolls)/\(trimmed.awakeBodies)"
        return "Transients: \(populations) — \(removed)"
    }
}
