// Cloak pulses: once a second, each running cloak casts its spell on the hostile actors
// inside its radius.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

extension MagicCoordinator.CloakPulses {
    /// Once per `cloakPulseSeconds`, casts each cloak's spell on the hostile actors inside
    /// its radius in feet. A cloak its conditions suspend casts nothing.
    func pulseCloaks(delta: Float) {
        guard delta.isFinite, delta > 0 else { return }
        coordinator.cloakClock += delta
        guard coordinator.cloakClock >= Self.cloakPulseSeconds else { return }
        coordinator.cloakClock = min(
            coordinator.cloakClock - Self.cloakPulseSeconds,
            Self.cloakPulseSeconds
        )
        guard let runtime = coordinator.effects else { return }
        for holder in coordinator.world.regeneratingHolders() {
            for effect in runningCloaks(on: holder, runtime: runtime) {
                pulse(effect, from: holder, world: coordinator.world)
            }
        }
    }

    func runningCloaks(on holder: ActorValueHolder, runtime: ActiveEffectRuntime)
        -> [ActiveEffect]
    {
        runtime.active(on: holder).filter {
            !$0.isSuspended && runtime.rule(of: $0) == .world(.cloak)
        }
    }

    func pulse(
        _ cloak: ActiveEffect,
        from holder: ActorValueHolder,
        world: any MagicWorld
    ) {
        guard
            let item = coordinator.associatedItem(of: cloak.effect),
            let spell = coordinator.caster?.spellbook.spells.spell(item)
        else { return }
        let radius = cloak.peakMagnitude * Self.unitsPerFoot
        let targets = world.cloakTargets(around: holder.key, radius: radius)
            .filter { $0 != holder.key }
        guard !targets.isEmpty else { return }
        let payload = spell.payload(caster: holder.key)
        coordinator.casterBridge.applySpellHit(SpellHit(
            payload: payload,
            targets: targets.map { SpellHitTarget(key: $0) }
        ))
        world.knock(targets, awayFrom: holder.key, by: payload)
    }

    /// How often a cloak casts its spell on the actors around it. An OpenSky
    /// number: the wiki names no rate, and a per-second effect pays on whole seconds.
    static let cloakPulseSeconds: Float = 1

    /// A cloak's magnitude is a radius in feet (<https://ck.uesp.net/wiki/Magic_Effect>),
    /// and 128 units are 6 feet (<https://ck.uesp.net/wiki/Unit>).
    static let unitsPerFoot: Float = 128.0 / 6.0
}
