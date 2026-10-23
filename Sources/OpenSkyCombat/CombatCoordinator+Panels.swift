// The readouts and controls of the Combat & Physics readout and the AI combat
// section, read off the runtimes `CombatCoordinator` owns.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics
import simd

extension CombatCoordinator {
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
    public func requestMeleeAttack() -> MeleeActionOutcome {
        requestMelee(power: false)
    }

    private func requestMelee(power: Bool) -> MeleeActionOutcome {
        guard let melee else { return .unavailable }
        guard melee.state.drawState.canAttack else {
            lastMeleeAction = .cannotAttack(melee.state.drawState)
            return lastMeleeAction
        }
        if power {
            melee.requestPowerAttack()
        } else {
            melee.requestAttack()
        }
        lastMeleeAction = .requested(power: power)
        return lastMeleeAction
    }

    /// The arrow settings, and what they did this session.
    static func arrowLines(_ projectiles: ProjectileRuntime) -> [String] {
        let arrows = projectiles.arrows
        return [
            String(format: "fCombatMissileStickDepth = %.3f", arrows.stickDepth),
            String(format: "fAttachedArrowAgeMax = %.3f", arrows.attachedAgeMax),
            "iArrowInventoryChance = \(arrows.inventoryChance)",
            "Arrows in actors: \(projectiles.attached.expiry.count), "
                + "kept by targets: \(projectiles.attached.recoveredCount)"
        ]
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
            enchantment: record.enchantment?.describedLine,
            strike: strikeText(record)
        )
    }

    private static func strikeText(_ record: MeleeHitRecord) -> String? {
        let strike = record.damage.strike
        var parts: [String] = []
        switch record.kind {
        case .normal: break
        case .power: parts.append("power attack")
        case .bash: parts.append("bash")
        case .powerBash: parts.append("power bash")
        }
        if strike.isSneakAttack {
            parts.append(String(format: "sneak attack x%.1f", strike.sneakMultiplier))
        }
        if strike.skillMultiplier != 1 {
            parts.append(String(format: "skill x%.2f", strike.skillMultiplier))
        }
        if strike.armorFraction > 0 {
            parts.append(String(format: "armour stopped %.0f%%", strike.armorFraction * 100))
        }
        if strike.perkMultiplier != 1 || strike.weaponDamageBonus != 0 {
            parts.append(String(
                format: "perks x%.2f %+.0f", strike.perkMultiplier, strike.weaponDamageBonus
            ))
        }
        if strike.isCritical {
            parts.append(String(format: "critical +%.0f", strike.criticalDamage))
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

extension CombatCoordinator {
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
                + Self.arrowLines(projectiles)
        )
    }

    /// Fires through the same `loose` the graph's `arrowRelease` uses, so a
    /// forced shot is the same downstream as a player shot.
    @discardableResult
    public func spawnDevProjectile() -> ArcheryActionOutcome {
        guard let archery else { return .unavailable }
        archery.arrow = selectedArrow()
        guard archery.arrow != nil else {
            lastArcheryAction = .noAmmunition
            return lastArcheryAction
        }
        guard let projectile = archery.loose(consumesArrow: false) else {
            lastArcheryAction = .noLaunchSpeed
            return lastArcheryAction
        }
        lastArcheryAction = .fired(
            id: projectile.id, speed: simd_length(projectile.state.velocity)
        )
        return lastArcheryAction
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

extension CombatCoordinator {
    public var combatLoopSnapshot: CombatLoopSnapshot {
        guard let loop else { return .unavailable }
        let selected = world.selectedActor()
        var snapshot = CombatLoopSnapshot(
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
            lastActionText: loop.lastAction.text
        )
        snapshot.usesTemperament = usesTemperament
        snapshot.combatAI = combatAI
        snapshot.isInInterior = world.isInInterior
        snapshot.allies = loop.allies(of: .player).map { allyLine($0, loop: loop) }
        if let selected, selected != .player {
            snapshot.selectedTemperament = combatTemperament(of: selected, toward: .player)
            snapshot.selectedAssistance = world.actorValues(of: selected)?(Self.assistanceIndex)
                .map(CombatAssistance.init(value:))
        }
        return snapshot
    }

    private func allyLine(_ key: ReferenceKey, loop: CombatLoopRuntime) -> String {
        let doing = if loop.behaviors[key]?.isEngaged == true, let foe = loop.targets[key] {
            "fighting \(actorName(foe))"
        } else if loop.following[key] != nil {
            "following the player"
        } else {
            "beside the player"
        }
        return "\(actorName(key)): \(doing)"
    }

    /// Reads the persisted Confidence and Assistance and game combat settings switches.
    public func load(settings store: PlayerSettingsStore) {
        usesTemperament = store.bool(.combatTemperament)
        appliesCombatGameSettings = store.bool(.combatGameSettings)
    }

    public var usesCombatTemperament: Bool {
        get { usesTemperament }
        set { usesTemperament = newValue }
    }

    public var selectedActorIsHostile: Bool {
        get {
            guard let loop, let key = world.selectedActor() else { return false }
            return loop.hostility(of: key) == .hostile
        }
        set { setSelectedActorHostile(newValue) }
    }

    public var isActorCastingEnabled: Bool {
        get { allowsActorCasting }
        set { setActorCasting(newValue) }
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
