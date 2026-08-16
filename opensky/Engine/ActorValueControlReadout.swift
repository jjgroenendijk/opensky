// Actor-value readout lines (issue #194, roadmap item 15.3), written for the
// M15 gate panel (issue #198) and formatted here rather than in the panel
// section for the reason `CombatLoopReadout`, `RagdollReadout`,
// `ArcheryReadout` and `MeleeCombatReadout` are: a string a milestone gate
// asserts on belongs in the engine target, where a unit test can reach it
// without a window.
//
// Documented in docs/engine/actor-values.md.

import Foundation

nonisolated enum ActorValueControlReadout {
    /// One actor's three bars, current over maximum.
    ///
    /// The label is the caller's rather than the readout's, because the same
    /// formatting serves the player line and the nearest-actor line and only
    /// the caller knows which it is asking for.
    static func barsText(_ label: String, for readout: ActorValueReadout) -> String {
        let bars = ActorValueKind.allCases.map { kind in
            String(
                format: "%@ %.0f/%.0f",
                kind.shortLabel,
                readout.current[kind],
                readout.maximums[kind]
            )
        }.joined(separator: "  ")
        let zero = readout.hasZeroHealth ? "  (down)" : ""
        return "\(label): \(readout.name) — \(bars)\(zero)"
    }

    /// The player's line, always present when a runtime is attached.
    static func playerText(for snapshot: ActorValueControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Player: unavailable" }
        return barsText("Player", for: snapshot.player)
    }

    /// The nearest resident actor's line, or the honest absence of one.
    static func nearestActorText(for snapshot: ActorValueControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Nearest actor: unavailable" }
        guard let nearest = snapshot.nearestActor else {
            return "Nearest actor: none resident"
        }
        return barsText("Nearest actor", for: nearest)
    }

    /// How the maximums above were arrived at, which is what explains an
    /// unexpected number more often than anything else on this readout.
    static func derivationText(for snapshot: ActorValueControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Derivation: unavailable" }
        let readout = snapshot.nearestActor ?? snapshot.player
        let spread = readout.autoCalculatesStats
            ? "auto-calculated per level"
            : "taken from the record"
        return "Derivation: level \(readout.level), \(spread)"
            + String(
                format: "  regen %.1f/%.1f/%.1f %%/s",
                readout.regenPercentPerSecond.health,
                readout.regenPercentPerSecond.magicka,
                readout.regenPercentPerSecond.stamina
            )
    }

    /// The selected actor value: what it reads, what its base and modifiers
    /// say, and — for a percentage resistance — the capped fraction of damage
    /// it removes (issue #468, roadmap item 19.5).
    ///
    /// The modifier slots are shown even when they are all zero, because a
    /// value at 40 with a base of 40 and a value at 40 with a base of 100 and
    /// 60 points of damage are different states the bar alone cannot tell
    /// apart.
    static func selectionText(for snapshot: ActorValueControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Selected value: unavailable" }
        let selection = snapshot.selection
        let resistance = selection.resistanceFraction.map {
            String(format: "  resists %.0f%% (capped)", $0 * 100)
        } ?? ""
        return String(
            format: "Selected value: %@ (%d) — %.1f  base %.1f  perm %+.1f  temp %+.1f"
                + "  dmg %+.1f%@",
            selection.name,
            selection.index,
            selection.current,
            selection.base,
            selection.permanent,
            selection.temporary,
            selection.damage,
            resistance
        )
    }

    /// Which target the dev controls act on, how many references carry runtime
    /// values, and what the last action did.
    static func controlsText(for snapshot: ActorValueControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Controls: unavailable" }
        let target = snapshot.target == .player ? "player" : "nearest actor"
        return "Controls: acting on the \(target)"
            + " — \(snapshot.runtimeActorCount) references carry runtime values"
            + "\n\(snapshot.lastActionText)"
    }
}

nonisolated extension ActorValueKind {
    /// The three-letter tag the panel's bar line uses. Spelled out here rather
    /// than derived from `rawValue` so a renamed case cannot silently change a
    /// readout a gate asserts on.
    var shortLabel: String {
        switch self {
        case .health: "HP"
        case .magicka: "MP"
        case .stamina: "SP"
        }
    }
}
