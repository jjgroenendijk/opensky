// Casting at something other than yourself, by the MGEF DATA delivery value
// (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MGEF>). Aimed fires the PROJ,
// or for concentration applies to the aim ray target once a second. Target Actor and
// Touch apply to the aimed actor; Target Location lands at the aim point or as a rune.
// See docs/engine/spell-delivery.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

/// Which deliveries this build carries out.
nonisolated public enum SpellDelivery: Sendable {
    /// Whether a cast of `delivery` runs rather than being refused.
    ///
    /// `castingType` decides for the deliveries whose two casting shapes are
    /// not equally implementable; a nil header reads as self delivery, which is
    /// the same fallback the cost calculation takes.
    public static func isImplemented(
        _ delivery: MagicEffectDelivery,
        castingType: MagicEffectCastingType?
    ) -> Bool {
        switch delivery {
        case .selfTarget, .aimed, .touch: true
        case .targetActor, .targetLocation: castingType != .concentration
        case .unknown: false
        }
    }
}

extension CasterRuntime {
    /// One application of a spell whose delivery takes it away from the caster.
    ///
    /// - Returns: how many timed effects were stored, which is zero for a
    ///   projectile — the effects land when it does, not when it is fired.
    public func deliverAway(
        _ payload: SpellPayload,
        spell: ResolvedSpell,
        delivery: MagicEffectDelivery,
        caster: ActorValueHolder,
        world: any CasterWorld
    ) -> Int {
        switch delivery {
        case .aimed where spell.data?.castingType != .concentration:
            guard world.fireSpellProjectile(payload) else { return 0 }
            tally.noteProjectile()
            return 0
        case .aimed, .targetActor:
            return applyAtAim(
                payload,
                range: spell.data?.range ?? 0,
                caster: caster.key,
                world: world
            )
        case .touch:
            return applyAtAim(payload, range: world.touchReach, caster: caster.key, world: world)
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

    /// Applies `payload` to whatever the caster's aim ray reaches.
    ///
    /// A ray that reaches nobody applies nothing and is not an error: sweeping
    /// a beam off a target between two applications is ordinary play, and the
    /// cast keeps running and keeps costing.
    private func applyAtAim(
        _ payload: SpellPayload,
        range: Float,
        caster: ReferenceKey,
        world: any CasterWorld
    ) -> Int {
        let aim = world.aimedSpellTarget(within: range, for: caster)
        let targets = SpellHitTargeting.targets(
            of: payload,
            at: aim.position,
            struck: aim.target,
            candidates: aim.candidates,
            excluding: payload.caster
        )
        guard !targets.isEmpty else { return 0 }
        let report = world.applySpellHit(SpellHit(
            payload: payload, targets: targets, impact: aim.position
        ))
        return report.storedCount
    }
}
