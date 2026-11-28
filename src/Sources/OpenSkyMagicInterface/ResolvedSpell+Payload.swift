// A resolved spell as the payload a delivery carries. Scripts and the caster
// runtime both build one.

public import OpenSkyFormatsESM
public import OpenSkyGameData

/// `nonisolated` because `ResolvedSpell` is, and isolation is per declaration
/// rather than per type: without this the closures below inherit the project's
/// `MainActor` default and a non-main caller traps.
nonisolated extension ResolvedSpell {
    /// This spell as the payload a delivery carries away from the caster.
    ///
    /// Everything is resolved once, here, and never re-derived downstream: a
    /// projectile in the air has to apply the spell that was cast rather than
    /// whatever the caster has readied by the time it lands.
    public func payload(caster: ReferenceKey) -> SpellPayload {
        var payload = SpellPayload(
            spell: key,
            sourcePlugin: sourcePlugin,
            caster: caster,
            entries: record.effects,
            // Any hostile entry makes the whole cast hostile: a spell that
            // damages and staggers is an attack even though the stagger entry
            // is not itself flagged.
            isHostile: effects
                .contains { $0.effect?.effect.data?.flags.contains(.hostile) == true },
            ignoresResistance: data?.flags.contains(.ignoreResistance) == true
                || spellType == .ability,
            // The first entry that names one. Vanilla authors the same PROJ on
            // every entry of a spell, so "first" and "the one" agree; a record
            // that disagreed would fire its first entry's projectile, which is
            // stated rather than silently picked.
            projectile: effects.compactMap { $0.effect?.effect.data?.projectile }.first,
            name: displayName
        )
        payload.baseCost = Float(cost.cost)
        payload.isConcentration = data?.castingType == .concentration
        payload.castingType = data?.castingType ?? .fireAndForget
        payload.delivery = data?.delivery ?? .aimed
        payload.disallowsAbsorb = data?.flags.contains(.disallowAbsorbReflect) == true
            || data?.flags.contains(.ignoreResistance) == true
        payload.areaIgnoresLineOfSight = data?.flags
            .contains(.areaEffectIgnoresLineOfSight) ?? false
        let launching = effects.lazy.compactMap(\.effect)
            .first { $0.effect.data?.projectile != nil }
        payload.impactDataSet = launching?.effect.data?.impactData
        payload.dualCastScale = launching?.effect.data?.dualCastScale ?? 1
        payload.dualCastArt = launching?.dualCastArt
        let flags = effects.compactMap { $0.effect?.effect.data?.flags }
        payload.sendsHitEvent = flags.isEmpty || flags.contains { !$0.contains(.noHitEvent) }
        payload.causesPain = spellType != .ability
            && flags.contains { $0.contains(.hostile) && !$0.contains(.painless) }
        return payload
    }
}
