// The readouts and controls of the Combat & Physics panel and the AI combat
// section, read off the runtimes `CombatCoordinator` owns.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics
import simd

extension CombatCoordinator: MeleeCombatControlProviding {
    public var isWeaponDrawn: Bool {
        get { melee?.state.drawState.isWeaponInHand ?? false }
        set { melee?.setWeaponDrawn(newValue) }
    }

    public var meleeCombatSnapshot: MeleeCombatSnapshot {
        guard let melee else { return .unavailable }
        let weapon = melee.weapon
        return MeleeCombatSnapshot(
            isAvailable: true,
            drawState: melee.state.drawState,
            attackPhase: melee.state.attackPhase,
            isBlocking: melee.state.isBlocking,
            isStaggering: melee.state.isStaggering,
            weaponName: weapon.weapon.map { items?.definition($0)?.editorID ?? $0.description }
                ?? "unarmed",
            weaponDamage: weapon.damage,
            weaponReachMultiplier: weapon.reach,
            weaponSpeed: weapon.speed,
            rightHandType: weapon.handType,
            leftHandType: melee.offHand,
            reach: melee.currentReach,
            swingCount: melee.swingCount,
            hitCount: melee.hitCount,
            trace: melee.trace.map(Self.readout),
            settings: melee.settings.report.map(Self.settingLine)
        )
    }

    @discardableResult
    public func requestMeleeAttack() -> String {
        guard let melee else { return "Melee unavailable: no game data loaded." }
        guard melee.state.drawState.canAttack else {
            meleeActionText = "Cannot attack: weapon is \(melee.state.drawState.rawValue)."
            return meleeActionText
        }
        melee.requestAttack()
        meleeActionText = "Requested one swing."
        return meleeActionText
    }

    public func clearMeleeTrace() {
        melee?.clearTrace()
        meleeActionText = "Cleared the hit trace."
    }

    static func settingLine(_ entry: (editorID: String, setting: MovementSetting)) -> String {
        String(
            format: "%@ = %.3f [%@]",
            entry.editorID,
            entry.setting.value,
            entry.setting.source
        )
    }

    private static func readout(_ record: MeleeHitRecord) -> MeleeHitReadout {
        MeleeHitReadout(
            target: record.target.description,
            distance: record.distance,
            baseDamage: record.damage.base,
            blockedPercent: record.damage.blockedFraction * 100,
            appliedDamage: record.damage.applied,
            sound: record.sound?.description,
            staggered: record.staggered,
            enchantment: record.enchantment?.describedLine
        )
    }
}

extension CombatCoordinator: ArcheryControlProviding {
    public var archerySnapshot: ArcherySnapshot {
        guard let archery else { return .unavailable }
        let projectiles = archery.projectiles
        let arrow = archery.arrow
        return ArcherySnapshot(
            isAvailable: true,
            phase: archery.state.phase,
            hasArrowAttached: archery.state.hasArrowAttached,
            heldSeconds: archery.heldSeconds,
            lastHeldSeconds: archery.lastHeldSeconds,
            drawFraction: ArcheryDamage.drawFraction(
                heldSeconds: archery.heldSeconds, speed: archery.bow.speed
            ),
            bowName: name(of: archery.bow.weapon) ?? "none",
            bowDamage: archery.bow.weapon == nil ? 0 : archery.bow.damage,
            bowSpeed: archery.bow.speed,
            arrowName: name(of: arrow?.item) ?? "none",
            arrowDamage: arrow?.damage ?? 0,
            projectileName: name(of: arrow?.profile.projectile) ?? "none",
            projectileSpeed: arrow?.profile.speed ?? 0,
            projectileGravityFactor: arrow?.profile.gravityFactor ?? 0,
            projectileRange: arrow?.profile.range ?? 0,
            drawRequestCount: archery.drawRequestCount,
            firedCount: projectiles.firedCount,
            impactCount: projectiles.impactCount,
            liveCount: projectiles.live.count,
            stuckCount: projectiles.stuck.count,
            trace: projectiles.trace.map(Self.readout),
            settings: archery.settings.report.map(Self.settingLine)
        )
    }

    /// Fires through the same `loose` the graph's `arrowRelease` uses, so a
    /// sidebar shot is the same downstream as a player shot.
    @discardableResult
    public func spawnDevProjectile() -> String {
        guard let archery else { return "Archery unavailable: no game data loaded." }
        archery.arrow = selectedArrow()
        guard archery.arrow != nil else {
            archeryActionText = "Cannot fire: no ammunition with a flyable PROJ carried."
            return archeryActionText
        }
        guard let projectile = archery.loose(consumesArrow: false) else {
            archeryActionText = "Cannot fire: the projectile has no launch speed."
            return archeryActionText
        }
        archeryActionText = String(
            format: "Fired projectile #%d at %.0f units/s.",
            projectile.id,
            simd_length(projectile.state.velocity)
        )
        return archeryActionText
    }

    public func despawnProjectiles() {
        archery?.projectiles.despawnAll()
        archeryActionText = "Despawned everything in flight."
    }

    public func clearStuckProjectiles() {
        archery?.projectiles.clearStuckArrows()
        archeryActionText = "Pulled every stuck arrow back out."
    }

    public func clearProjectileTrace() {
        archery?.projectiles.clearTrace()
        archeryActionText = "Cleared the shot trace."
    }

    /// The editor ID when the item index resolves one, else the FormID.
    private func name(of id: FormID?) -> String? {
        guard let id else { return nil }
        if let definition = items?.definition(id) {
            return definition.editorID ?? id.description
        }
        return items?.projectiles[id.rawValue]?.editorID ?? id.description
    }

    private static func readout(_ trace: ProjectileTrace) -> ProjectileTraceReadout {
        ProjectileTraceReadout(
            id: trace.id,
            launch: trace.launchPosition,
            end: trace.endPosition,
            flightTime: trace.flightTime,
            travelled: trace.travelled,
            drop: trace.drop,
            outcome: trace.outcome,
            target: trace.target?.description,
            appliedDamage: trace.appliedDamage,
            sound: trace.sound?.description,
            stuck: trace.stuck
        )
    }
}

extension CombatCoordinator: CombatLoopControlProviding {
    public var combatLoopSnapshot: CombatLoopSnapshot {
        guard let loop else { return .unavailable }
        let selected = world?.selectedActor()
        return CombatLoopSnapshot(
            isAvailable: true,
            isPlayerInCombat: loop.state.isPlayerInCombat,
            targetName: loop.state.target == nil ? "—" : loop.state.targetName,
            targetDistance: loop.state.targetDistance,
            hostileCount: loop.state.hostileCount,
            deadCount: loop.state.deadCount,
            engagedCount: loop.state.engagedCount,
            searchingCount: loop.state.searchingCount,
            actors: actorReadouts(loop: loop),
            crowdedOutCount: loop.crowdedOutCount,
            selectedActorName: actorName(selected),
            selectedActorIsHostile: selected.map { loop.hostility(of: $0) == .hostile } ?? false,
            incomingHitCount: loop.incomingHitCount,
            incomingTrace: loop.incomingTrace.map(CombatLoopReadout.traceLine(for:)),
            damageFlash: loop.playerDamageFlash,
            transients: combatTransients,
            limits: loop.limits,
            trimmedTransients: loop.trimmedTransients,
            isActorCastingEnabled: allowsActorCasting,
            actorCastCount: actorCastCount,
            lastActionText: loop.lastActionText
        )
    }

    public var selectedActorIsHostile: Bool {
        get {
            guard let loop, let key = world?.selectedActor() else { return false }
            return loop.hostility(of: key) == .hostile
        }
        set { setSelectedActorHostile(newValue) }
    }

    public var isActorCastingEnabled: Bool {
        get { allowsActorCasting }
        set { setActorCasting(newValue) }
    }

    public func clearCombatTrace() {
        loop?.clearTrace()
    }

    /// One line per actor with a behavior machine, nearest first, from the same
    /// observation the loop stepped against.
    private func actorReadouts(loop: CombatLoopRuntime) -> [CombatActorReadout] {
        let player = combatPlayer.feet
        return combatActors().compactMap { actor in
            guard let machine = loop.behaviors[actor.key] else { return nil }
            return CombatActorReadout(
                key: actor.key,
                name: actor.name,
                phase: machine.phase,
                awareness: combatAwareness(of: actor.key, toward: .player).state,
                distance: simd_distance(actor.feet, player),
                healthFraction: combatHealthFraction(of: actor.key),
                attackCount: machine.attackCount,
                contactCount: machine.contactCount,
                blockCount: machine.blockCount,
                searchCount: machine.searchCount,
                castCount: machine.castCount,
                spellOptionCount: combatCasting(of: actor.key).options.count
            )
        }
        .sorted { ($0.distance, $0.key) < ($1.distance, $1.key) }
    }
}
