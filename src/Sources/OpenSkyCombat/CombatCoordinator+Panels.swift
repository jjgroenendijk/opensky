// The readouts of the Combat & Physics readout and the AI combat section, read off
// the runtimes `CombatCoordinator` owns.

import OpenSkyActorsInterface
public import OpenSkyCombatInterface
import OpenSkyFormatsESM

extension CombatCoordinator {
    public var isWeaponDrawn: Bool {
        get { shared.melee?.isWeaponInHand ?? false }
        set { shared.melee?.setWeaponDrawn(newValue) }
    }

    public var meleeCombatSnapshot: MeleeCombatSnapshot {
        MeleeCombatSnapshot(melee: shared.melee)
    }

    public var combatLoopSnapshot: CombatLoopSnapshot {
        CombatLoopSnapshot(shared: shared)
    }

    public var projectileReadout: ProjectileReadout {
        PanelReadouts(owner: self).projectileReadout
    }

    public var assistReadout: CombatAssistReadout {
        PanelReadouts(owner: self).assistReadout
    }
}

extension MeleeCombatRuntime {
    var isWeaponInHand: Bool {
        state.drawState.isWeaponInHand
    }
}

extension MeleeCombatSnapshot {
    /// The hit count and trace, or `.unavailable` without game data.
    @MainActor
    init(melee: MeleeCombatRuntime?) {
        guard let melee else {
            self = .unavailable
            return
        }
        self.init(hitCount: melee.hitCount, trace: melee.trace.map(Self.readout))
    }

    private static func readout(_ record: MeleeHitRecord) -> MeleeHitReadout {
        MeleeHitReadout(
            target: record.target.description,
            appliedDamage: record.damage.applied
        )
    }
}

@MainActor
extension CombatLoopSnapshot {
    init(shared: CombatShared) {
        guard let loop = shared.loop else {
            self = .unavailable
            return
        }
        self.init(
            isPlayerInCombat: loop.state.isPlayerInCombat,
            hostileCount: loop.state.hostileCount,
            actorCastCount: shared.actorCastCount,
            lastActionText: loop.lastAction.text
        )
        usesTemperament = shared.usesTemperament
        combatAI = shared.combatAI
        isInInterior = shared.world.isInInterior
    }
}

extension CombatCoordinator {
    /// Builds the projectile and assist readouts.
    struct PanelReadouts {
        let owner: CombatCoordinator

        var projectileReadout: ProjectileReadout {
            let shared = owner.shared
            var readout = shared.archery?.projectiles.readout ?? ProjectileReadout()
            readout.lastKillCamCheck = shared.lastKillCamCheck
            return readout
        }

        var assistReadout: CombatAssistReadout {
            let loopWorld = owner.loopWorld
            let shared = owner.shared
            var readout = CombatAssistReadout()
            if let loop = shared.loop {
                readout.tracks = loop.attackTracks.keys.sorted().compactMap { key in
                    loop.attackTracks[key].map {
                        .init(
                            attacker: key,
                            target: $0.target,
                            aim: $0.aim,
                            refreshes: $0.refreshes
                        )
                    }
                }
                readout.attackPicks = loop.pickedAttacks.keys.sorted().compactMap { key in
                    loop.pickedAttacks[key].map {
                        .init(
                            attacker: key, event: $0.event, isPowerAttack: $0.isPowerAttack,
                            knockdown: $0.data.knockdown
                        )
                    }
                }
                readout.closeMoves = loop.behaviors.keys.sorted().compactMap { key in
                    loop.behaviors[key].flatMap { machine in
                        machine.settings.closeRange == nil ? nil : .init(
                            actor: key, current: machine.closeMoveKind,
                            started: machine.closeMoveCount
                        )
                    }
                }
                readout.guards = loop.behaviors.keys.sorted().compactMap { key in
                    loop.behaviors[key].flatMap { machine in
                        machine.settings.blockLoop == nil ? nil : .init(
                            actor: key, current: machine.guardKind,
                            raised: machine.loopGuardCount, bashes: machine.bashCount
                        )
                    }
                }
                readout.watches = loop.dangerWatches
                readout.threats = loopWorld.combatDangerThreats()
            }
            readout.autoAim = shared.archery?.projectiles.lastAutoAim
            readout.reactions = shared.hitReactions
            return readout
        }
    }
}
