// `state assist`: what the combat and AI helper rules do now.
// docs/engine/combat-assist.md, danger-avoidance.md, ai-process-levels.md, hit-reactions.md.

import OpenSkyAgentControl
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkySessionInterface
import OpenSkyWorldInterface

struct AgentAssistReadout {
    let hub: AgentHub

    func assistState() -> AgentJSON {
        let readout = hub.hosts.combat.assistReadout
        func key(_ key: ReferenceKey) -> AgentJSON {
            .string(key.description)
        }
        let tracks = readout.tracks.map { track -> AgentJSON in
            [
                "attacker": key(track.attacker), "target": key(track.target),
                "aim": .init(track.aim), "refreshes": .init(track.refreshes)
            ]
        }
        let threats = readout.threats.map { threat -> AgentJSON in
            [
                "id": .init(threat.id), "source": threat.source.map(key) ?? .null,
                "position": .init(threat.position), "velocity": .init(threat.velocity),
                "damage": .init(threat.damage), "radius": .init(threat.radius)
            ]
        }
        let watches = readout.watches.keys.sorted().map { actor -> AgentJSON in
            let watch = readout.watches[actor] ?? CombatDangerWatch()
            return [
                "actor": key(actor), "score": .init(watch.score),
                "dodgeSeconds": .init(max(0, watch.dodgeSeconds)),
                "dodges": .init(watch.dodgeCount),
                "dodgePoint": watch.dodge.map { .init($0.point) } ?? .null
            ]
        }
        return [
            "attackTracks": .array(tracks),
            "autoAim": readout.autoAim.map {
                ["target": key($0.target.key), "rightHandIsFree": .bool($0.rightHandIsFree)]
            } ?? .null,
            "magnetism": magnetismJSON(),
            "danger": ["threats": .array(threats), "watches": .array(watches)],
            "hitReactions": .array(readout.reactions.map(Self.reactionJSON)),
            "processLevels": .object(
                hub.hosts.packages.processReadout.mapValues { AgentJSON.number($0) }
            )
        ]
    }

    /// The melee magnetism switch, and the target and turn of the last frame that turned.
    private func magnetismJSON() -> AgentJSON {
        guard let tracker = hub.hosts.gameSession?.motion.magnetism else { return .null }
        return [
            "enabled": .bool(tracker.isEnabled),
            "turning": .bool(tracker.isTurning),
            "target": tracker.lastTarget.map { .string($0.actor?.description ?? "object") }
                ?? .null,
            "heading": .init(tracker.lastChange.heading),
            "pitch": .init(tracker.lastChange.pitch)
        ]
    }

    private static func reactionJSON(_ report: HitReactionReport) -> AgentJSON {
        let facts = report.hit.facts
        return [
            "attacker": .string(report.attacker.description),
            "target": .string(report.target.description),
            "attackStagger": .init(facts.attackStagger),
            "attackerBlock": .init(facts.attackerBlock),
            "targetMass": .init(facts.targetMass),
            "targetRuns": .bool(facts.targetRuns),
            "targetRecoils": .bool(facts.targetRecoils),
            "targetAttacks": .bool(facts.targetAttacks),
            "weaponFactor": .init(HitReactionRule.weaponFactor(report.hit)),
            "staggerMagnitude": report.reaction.staggerMagnitude.map { .init($0) } ?? .null,
            "staggerDirection": .init(facts.direction),
            "largeRecoil": .bool(report.reaction.largeRecoil),
            "blockHit": .bool(report.reaction.blockHit),
            "attackerRecoils": .bool(report.reaction.attackerRecoils)
        ]
    }
}

extension AgentAssistReadout {
    /// `state projectiles`: docs/engine/projectiles.md.
    func projectilesState() -> AgentJSON {
        let readout = hub.hosts.combat.projectileReadout
        return [
            "inFlight": .init(readout.inFlight), "bouncing": .init(readout.bouncing),
            "stuck": .array(readout.stuck.map { .string($0.description) }),
            "landings": .array(readout.landings.map { landing in
                [
                    "outcome": .string(landing.outcome), "position": .init(landing.position),
                    "target": landing.target.map { .string($0.description) } ?? .null,
                    "material": landing.material.map { .string($0.description) } ?? .null,
                    "stuck": .bool(landing.stuck), "bounced": .bool(landing.bounced),
                    "damage": .init(landing.damage),
                    "spellTargets": landing.spellTargets.map { .init($0) } ?? .null,
                    "spellEntries": landing.spellEntries.map { .init($0) } ?? .null,
                    "spellRefusals": landing.spellRefusals.map { .init($0) } ?? .null,
                    "spellMagnitudes": .array(landing.spellMagnitudes.map { .init($0) })
                ]
            })
        ]
    }
}
