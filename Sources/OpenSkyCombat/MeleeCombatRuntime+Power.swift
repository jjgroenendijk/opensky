// Power attacks and bashes: which start event a press raises, what it costs,
// and how it changes the hit. See docs/engine/melee-damage.md, "Power attacks and bashes".

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPhysics

extension MeleeCombatRuntime {
    /// Latches one held press, as if the button stayed down past the delay. What the
    /// readout's Power attack button calls; with the guard up it is a power bash.
    public func requestPowerAttack() {
        pendingAttack = true
        pendingPower = true
    }

    /// Raises the start event once the press is released or held long enough.
    func resolveHold(_ intent: MeleeIntent, world: any MeleeCombatWorld) {
        let forced = pendingPower
        pendingPower = false
        let outcome = hold.advance(
            held: intent.attackHeld || forced,
            deltaTime: forced ? MeleeHold.powerAttackDelay : intent.deltaTime
        )
        if let outcome {
            queuedOutcome = outcome
        }
        // Mid-swing, a press waits for the combo window, so the graph takes the
        // start event. It is dropped when the swing ends first.
        guard
            let queued = queuedOutcome,
            !state.attackPhase.isAttacking || state.isChainWindowOpen
        else { return }
        queuedOutcome = nil
        let direction = MeleePowerDirection(
            moveForward: intent.moveForward, moveRight: intent.moveRight
        )
        switch queued {
        case let .tapped(kind):
            start(kind, direction: direction, world: world)
        case let .held(kind):
            if pay(for: kind, world: world) {
                start(kind, direction: direction, world: world)
            } else {
                start(kind.isBash ? .bash : .normal, direction: direction, world: world)
            }
        }
    }

    /// The hit of the swing in progress, with its power or bash terms.
    func resolveDamage(on target: ReferenceKey, world: any MeleeCombatWorld) -> MeleeDamageResult {
        var strike = world.meleeStrike(blow(world: world), on: target)
        if strikeKind == .power {
            strike.powerMultiplier *= 1 + powerAttacks.damageBonus
        }
        var swing = weapon
        if strikeKind.isBash {
            let source = world.meleeBashSource()
            swing = weapon.dealing(damage: strike.bashMultiplier * MeleeBash.damage(
                BashSource(
                    weaponDamage: weapon.damage,
                    shieldRating: source.shieldRating,
                    blockSkill: source.blockSkill
                ),
                isPlayer: true,
                isPower: strikeKind == .powerBash,
                settings: powerAttacks
            ))
        }
        return MeleeDamage.resolve(
            weapon: swing,
            block: world.meleeBlock(of: target),
            settings: settings,
            isPowerAttack: strikeKind.isPowerAttack,
            bonusMultiplier: world.meleeBlockMultiplier(of: target),
            attackMultiplier: strikeKind.isBash
                ? 1 : world.meleeAttackMultiplier(handType: weapon.handType),
            strike: strike
        )
    }

    /// The swing in progress, as the perk terms read it.
    func blow(world: any MeleeCombatWorld) -> CombatBlow {
        CombatBlow(
            attacker: world.meleeAttacker.key,
            weapon: weapon.weapon,
            handType: weapon.handType,
            kind: strikeKind,
            baseDamage: weapon.damage
        )
    }

    /// CK wiki "Perk Entry Point", Set Sweep Attack: without the perk a swing strikes
    /// the nearest actor once.
    func struck(_ hits: [MeleeHit], world: any MeleeCombatWorld) -> [MeleeHit] {
        guard let nearest = hits.first, !world.meleeSweeps(blow(world: world)) else { return hits }
        return hitThisSwing.isEmpty ? [nearest] : []
    }

    /// A bash reaches `fCombatBashReach` whatever the weapon.
    func strikeReach(actorScale: Float) -> Float {
        guard strikeKind.isBash else {
            return MeleeSwing.reach(weapon: weapon, settings: settings, actorScale: actorScale)
        }
        let scale = actorScale.isFinite && actorScale > 0 ? actorScale : 1
        return max(0, powerAttacks.bashReach) * scale
    }

    /// A bash costs its stamina at the start; with too little the press does nothing.
    private func start(
        _ kind: MeleeStrikeKind, direction: MeleePowerDirection, world: any MeleeCombatWorld
    ) {
        if kind == .bash, !world.payMeleeStamina(powerAttacks.bashStamina) {
            return
        }
        strikeKind = kind
        powerDirection = kind == .power ? direction : nil
        let event = switch kind {
        case .normal: CombatGraphNames.attackStart
        case .power: direction.eventName
        case .bash: CombatGraphNames.bashStart
        case .powerBash: CombatGraphNames.bashPowerStart
        }
        if kind == .power {
            hold.startedPowerAttack(coolDown: powerAttacks.coolDown)
        }
        world.raiseCombatEvent(event, on: nil)
    }

    /// UESP "Skyrim:Combat": with less than one point of stamina a held press
    /// plays the plain attack instead. A power bash also needs the Power Bash perk.
    private func pay(for kind: MeleeStrikeKind, world: any MeleeCombatWorld) -> Bool {
        switch kind {
        case .power:
            world.payMeleeStamina(world.meleePowerAttackStamina(
                powerAttacks.powerAttackStamina(weight: weapon.weight), weapon: weapon.weapon
            ))
        case .powerBash:
            world.canPowerBash() && world.payMeleeStamina(powerAttacks.powerBashStamina)
        case .normal, .bash:
            true
        }
    }
}

/// What a bash strikes with: the shield's base rating, or the weapon's base damage
/// without a shield, and the basher's Block skill.
nonisolated public struct BashSource: Equatable, Sendable {
    public var weaponDamage: Float
    public var shieldRating: Float?
    public var blockSkill: Float

    public init(weaponDamage: Float, shieldRating: Float?, blockSkill: Float) {
        self.weaponDamage = weaponDamage
        self.shieldRating = shieldRating
        self.blockSkill = blockSkill
    }
}

/// Bash damage, from UESP "Skyrim:Block": half the weapon's base damage or the
/// shield's base rating, times a factor the Block skill moves between two settings.
nonisolated public enum MeleeBash: Sendable {
    public static func damage(
        _ source: BashSource, isPlayer: Bool, isPower: Bool, settings: PowerAttackSettings
    ) -> Float {
        let range = source.shieldRating == nil ? settings.weaponBash : settings.shieldBash
        let raw = source.shieldRating ?? source.weaponDamage
        let base = raw.isFinite ? max(0, raw) : 0
        let power = isPower ? PowerAttackSettings.powerBashMultiplier : 1
        let factor = range.factor(blockSkill: source.blockSkill, isPlayer: isPlayer)
        return base * 0.5 * factor * power
    }
}
