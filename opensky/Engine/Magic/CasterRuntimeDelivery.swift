// Casting at something other than yourself (issue #471, roadmap item 19.8):
// which deliveries this build carries out, how a cast turns into a payload, and
// what each delivery does with it.
//
// The delivery vocabulary is the record's own, decoded in `MagicEffectEnums`
// from UESP's MGEF DATA table — 0 Self, 1 Touch, 2 Aimed, 3 Target Actor,
// 4 Target Location (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MGEF>).
// UESP's Magic Overview describes the shapes those numbers stand for: "Spells
// that don't target the one using them vary in range: some only work on touch,
// several are fired as projectiles, some are maintained as a short-ranged
// spray, and a few (primarily Master level spells) affect everything within a
// certain distance of the caster."
// (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>)
//
// ## What is carried, and what is counted
//
// | Delivery | Fire and forget | Concentration |
// |---|---|---|
// | Self | applies to the caster | applies to the caster once a second |
// | Aimed | fires the MGEF's PROJ | applies to whatever the aim ray reaches, once a second |
// | Target Actor | applies to whatever the aim ray reaches, within SPIT range | counted |
// | Touch | counted | counted |
// | Target Location | counted | counted |
//
// **Touch and Target Location are refused and counted rather than approximated,
// and the reason is different for each.** Touch needs the melee-reach geometry
// and the contact frame the animation graph owns (M25/M26); approximating it as
// a zero-range aimed cast would land a "touch" spell at the far end of a room.
// Target Location places an effect on the ground, which in vanilla is an EXPL
// or a rune placement — the EXPL runtime is explicitly out of this item's scope
// and is milestone M26, so there is nowhere for the effect to live.
//
// The concentration cadence is not invented here: it is the one
// `CasterRuntime.maintain` already runs for a self-delivery concentration
// spell — once on entry and once per whole second held — so a flamethrower and
// a maintained heal tick together. What changes for an aimed concentration cast
// is only *who* each application lands on: the aim ray is resampled every
// application, so sweeping a beam off a target stops applying to it, which is
// what "repeated short-interval application to whatever the aim ray hits"
// means.
//
// Documented in docs/engine/magic.md.

import Foundation

/// Which deliveries this build carries out.
nonisolated enum SpellDelivery {
    /// Whether a cast of `delivery` runs rather than being refused.
    ///
    /// `castingType` decides for the deliveries whose two casting shapes are
    /// not equally implementable; a nil header reads as self delivery, which is
    /// the same fallback the cost calculation takes.
    static func isImplemented(
        _ delivery: MagicEffectDelivery,
        castingType: MagicEffectCastingType?
    ) -> Bool {
        switch delivery {
        case .selfTarget, .aimed: true
        case .targetActor: castingType != .concentration
        case .touch, .targetLocation, .unknown: false
        }
    }
}

/// `nonisolated` because `ResolvedSpell` is, and isolation is per declaration
/// rather than per type: without this the closures below inherit the project's
/// `MainActor` default and a non-main caller traps.
nonisolated extension ResolvedSpell {
    /// This spell as the payload a delivery carries away from the caster.
    ///
    /// Everything is resolved once, here, and never re-derived downstream: a
    /// projectile in the air has to apply the spell that was cast rather than
    /// whatever the caster has readied by the time it lands.
    func payload(caster: ReferenceKey) -> SpellPayload {
        SpellPayload(
            spell: key,
            sourcePlugin: sourcePlugin,
            caster: caster,
            entries: record.effects,
            // Any hostile entry makes the whole cast hostile: a spell that
            // damages and staggers is an attack even though the stagger entry
            // is not itself flagged.
            isHostile: effects
                .contains { $0.effect?.effect.data?.flags.contains(.hostile) == true },
            ignoresResistance: data?.flags.contains(.ignoreResistance) ?? false,
            // The first entry that names one. Vanilla authors the same PROJ on
            // every entry of a spell, so "first" and "the one" agree; a record
            // that disagreed would fire its first entry's projectile, which is
            // stated rather than silently picked.
            projectile: effects.compactMap { $0.effect?.effect.data?.projectile }.first,
            name: displayName
        )
    }
}

extension CasterRuntime {
    /// One application of a spell whose delivery takes it away from the caster.
    ///
    /// - Returns: how many timed effects were stored, which is zero for a
    ///   projectile — the effects land when it does, not when it is fired.
    func deliverAway(
        _ spell: ResolvedSpell,
        delivery: MagicEffectDelivery,
        caster: ActorValueHolder,
        world: any CasterWorld
    ) -> Int {
        let payload = spell.payload(caster: caster.key)
        switch delivery {
        case .aimed where spell.data?.castingType != .concentration:
            guard world.fireSpellProjectile(payload) else { return 0 }
            tally.noteProjectile()
            return 0
        case .aimed, .targetActor:
            return applyAtAim(payload, range: spell.data?.range ?? 0, world: world)
        case .selfTarget, .touch, .targetLocation, .unknown:
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
        world: any CasterWorld
    ) -> Int {
        let aim = world.aimedSpellTarget(within: range)
        let targets = SpellHitTargeting.targets(
            of: payload,
            at: aim.position,
            struck: aim.target,
            candidates: aim.candidates,
            excluding: payload.caster
        )
        guard !targets.isEmpty else { return 0 }
        let report = world.applySpellHit(SpellHit(
            payload: payload, position: aim.position, targets: targets
        ))
        return report.storedCount
    }
}
