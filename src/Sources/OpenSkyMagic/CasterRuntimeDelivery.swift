// Casting by the MGEF DATA delivery value
// (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MGEF>). Self with an area
// spreads around the caster. Aimed fires the PROJ,
// or for concentration applies to the aim ray target once a second. Target Actor and
// Touch apply to the aimed actor; Target Location lands at the aim point or as a rune.
// See docs/engine/spell-delivery.md.

import Foundation
import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMagicInterface
import OpenSkyPhysics

extension CasterRuntime {
    /// One application of a spell whose delivery takes it away from the caster.
    ///
    /// - Returns: how many timed effects were stored, which is zero for a
    ///   projectile — the effects land when it does, not when it is fired.
    public func deliverAway(
        _ payload: SpellPayload,
        spell: ResolvedSpell,
        caster: ActorValueHolder,
        world: any CasterWorld
    ) -> Int {
        let delivery = spell.data?.delivery ?? .selfTarget
        switch delivery {
        case .aimed where spell.data?.castingType != .concentration:
            guard world.fireSpellProjectile(payload) else { return 0 }
            tally.noteProjectile()
            return 0
        case .aimed, .targetActor:
            return world.applyAtAim(
                payload,
                range: spell.data?.range ?? 0,
                caster: caster.key
            )
        case .touch:
            return world.applyAtAim(payload, range: world.touchReach, caster: caster.key)
        case .targetLocation:
            return world.deliverToLocation(payload, spell: spell, caster: caster)
        case .selfTarget, .unknown:
            // Unreachable: `SpellDelivery.isImplemented` refused these before
            // the cast started, and self delivery never gets here. Returning
            // zero rather than trapping keeps a mod-authored delivery this
            // build has not seen a no-op instead of a crash.
            return 0
        }
    }
}

extension CasterWorld {
    /// Applies `payload` to whatever the caster's aim ray reaches.
    ///
    /// A ray that reaches nobody applies nothing and is not an error: sweeping
    /// a beam off a target between two applications is ordinary play, and the
    /// cast keeps running and keeps costing.
    func applyAtAim(
        _ payload: SpellPayload,
        range: Float,
        caster: ReferenceKey
    ) -> Int {
        let aim = aimedSpellTarget(within: range, for: caster)
        let targets = SpellHitTargeting.targets(
            of: payload,
            landing: (aim.position, aim.target),
            candidates: aim.candidates,
            excluding: payload.caster
        )
        guard !targets.isEmpty else { return 0 }
        let report = applySpellHit(SpellHit(
            payload: payload, targets: targets, impact: aim.position
        ))
        return report.storedCount
    }

    /// A self cast. CK wiki "Spell": "effects with a non-zero Area are AoEs centered
    /// at the caster, affecting every actor in range *except* the caster".
    func applyFromSelf(
        _ payload: SpellPayload,
        spell: ResolvedSpell,
        caster: ActorValueHolder
    ) -> Int {
        let onCaster = payload.entries.filter { $0.area == 0 }
        var stored = 0
        if !onCaster.isEmpty {
            stored = applyCastEffects(
                onCaster,
                origin: (spell.sourcePlugin, ActiveEffectSource(kind: .spell, record: spell.key)),
                caster: caster.key,
                on: caster
            )
        }
        guard onCaster.count < payload.entries.count else { return stored }
        let candidates = spellHitCandidates()
        guard let centre = candidates.first(where: { $0.key == caster.key }) else { return stored }
        let position = centre.feet + SIMD3(0, 0, centre.capsule.height / 2)
        let targets = SpellHitTargeting.targets(
            of: payload, landing: (position, nil), candidates: candidates, excluding: caster.key
        )
        guard !targets.isEmpty else { return stored }
        let report = applySpellHit(SpellHit(
            payload: payload, targets: targets, impact: position
        ))
        return stored + report.storedCount
    }
}
