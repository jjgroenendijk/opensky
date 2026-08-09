// Combat-loop readout lines (issues #374 and #424, roadmap items 15.7 and
// 16.7), formatted here rather than in the panel section for the reason
// `RagdollReadout`, `ArcheryReadout` and `MeleeCombatReadout` are: a string a
// milestone gate asserts on belongs in the engine target, where a unit test can
// reach it without a window.
//
// The dev-target line is gone with the dev target. What replaced it is one line
// per fighting actor — who, in which phase, how far away, how hurt, and what it
// currently makes of the player — which is scope point 8's "real per-actor
// combat readout" and what item 16.8's gate panel is written against.
//
// Documented in docs/engine/combat.md.

import Foundation

/// One fighting actor as the panel shows it.
nonisolated struct CombatActorReadout: Equatable, Sendable {
    let key: ReferenceKey
    /// FULL name when one resolves, else the editor ID, else the FormID.
    let name: String
    let phase: CombatBehaviorPhase
    /// How aware it is of the player right now.
    let awareness: DetectionState
    /// Distance to the player, world units.
    let distance: Float
    /// Its health over its maximum, 0 through 1.
    let healthFraction: Float
    /// Attacks started, contact steps reached, guards raised and searches begun
    /// since it first fought.
    let attackCount: Int
    let contactCount: Int
    let blockCount: Int
    let searchCount: Int
}

nonisolated enum CombatLoopReadout {
    /// Whether the player is fighting, and whom.
    static func stateText(for snapshot: CombatLoopSnapshot) -> String {
        guard snapshot.isAvailable else { return "Combat: unavailable" }
        guard snapshot.isPlayerInCombat else {
            return "Combat: out of combat"
                + " (\(snapshot.hostileCount) hostile, \(snapshot.deadCount) dead nearby)"
        }
        return "Combat: in combat with \(snapshot.targetName)"
            + String(format: " at %.0f u", snapshot.targetDistance)
            + " (\(snapshot.engagedCount) engaged, \(snapshot.searchingCount) searching,"
            + " \(snapshot.hostileCount) hostile, \(snapshot.deadCount) dead)"
    }

    /// One line per actor with a combat machine, newest state each frame.
    static func actorsText(for snapshot: CombatLoopSnapshot) -> String {
        guard snapshot.isAvailable else { return "Fighters: unavailable" }
        guard !snapshot.actors.isEmpty else { return "Fighters: none" }
        let crowded = snapshot.crowdedOutCount > 0
            ? " (\(snapshot.crowdedOutCount) over the engagement cap)"
            : ""
        let header = "Fighters: \(snapshot.actors.count)\(crowded)"
        return ([header] + snapshot.actors.map { "  \(actorLine(for: $0))" })
            .joined(separator: "\n")
    }

    /// One fighting actor as a readout line.
    static func actorLine(for actor: CombatActorReadout) -> String {
        let situation = String(
            format: "%.0f u, health %.0f%%", actor.distance, actor.healthFraction * 100
        )
        let counts = "\(actor.attackCount) attacks, \(actor.contactCount) contact frames,"
            + " \(actor.blockCount) blocks, \(actor.searchCount) searches"
        return "\(actor.name): \(actor.phase.rawValue), \(actor.awareness.rawValue), "
            + situation + " — " + counts
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
