// What a fighting NPC can cast, and the cast calls the combat loop makes. An
// NPC casts through the same spellbook and cast loop the player's Cast button
// uses; only the caster differs (docs/engine/ai-spell-use.md).

import OpenSkyActors
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMagicInterface

extension CombatWorldAdapter {
    /// Vanilla NPCs cast from either hand. OpenSky picks the right one, which
    /// is a simplification, not an observation.
    static let castHand = SpellHand.right

    func castingFacts(of key: ReferenceKey) -> CombatCastingFacts? {
        guard
            let runtime = game.magic.caster,
            let values = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: key)
        else { return nil }
        game.magic.grantAuthoredSpells(to: holder)
        return CombatCastingFacts(
            magicka: values.current(of: holder).magicka,
            spells: runtime.spellbook.knownSpells(of: holder)
                .map { candidate($0, runtime: runtime) },
            shouts: game.magic.npcShouts(of: holder).compactMap(shoutOption)
        )
    }

    @discardableResult
    func shout(_ spell: ReferenceKey, by key: ReferenceKey) -> Bool {
        guard let holder = game.actorWorld.actorValueHolder(for: key) else { return false }
        return game.magic.npcShout(spell, by: holder)
    }

    /// A shout as its strongest word with a spell. An NPC has no Shout Recovery Mult, so
    /// the word's own recovery time is the cooldown.
    private func shoutOption(_ shout: ResolvedShout) -> CombatSpellOption? {
        guard let word = shout.words.last(where: { $0.spell != nil }), let spell = word.spell
        else { return nil }
        return CombatSpellOption(
            spell: spell.key,
            cost: 0,
            range: game.magicWorld.castReach(within: spell.data?.range ?? 0),
            purpose: .shout,
            cooldownSeconds: ShoutCore.cooldown(recovery: word.entry.recoveryTime, multiplier: 1)
        )
    }

    @discardableResult
    func beginCast(_ spell: ReferenceKey, by key: ReferenceKey) -> Bool {
        guard
            let runtime = game.magic.caster,
            let holder = game.actorWorld.actorValueHolder(for: key),
            (try? runtime.spellbook.equip(spell, in: Self.castHand, on: holder)) != nil
        else { return false }
        return runtime.begin(Self.castHand, on: holder).failure == nil
    }

    /// A maintained cast under its SPIT minimum keeps running after release.
    /// An NPC has no button still held, so that cast is dropped instead.
    @discardableResult
    func releaseCast(by key: ReferenceKey) -> Bool {
        guard
            let runtime = game.magic.caster,
            let holder = game.actorWorld.actorValueHolder(for: key)
        else { return false }
        let outcome = runtime.release(Self.castHand, on: holder)
        if runtime.phase(of: Self.castHand, on: key).isCasting {
            runtime.cancel(Self.castHand, on: holder)
        }
        return outcome.isFinished
    }

    func cancelCast(by key: ReferenceKey) {
        guard
            let runtime = game.magic.caster,
            let holder = game.actorWorld.actorValueHolder(for: key)
        else { return }
        runtime.cancel(Self.castHand, on: holder)
    }

    private func candidate(_ spell: ResolvedSpell, runtime: CasterRuntime) -> CombatSpellCandidate {
        let delivery = spell.data?.delivery ?? .selfTarget
        return CombatSpellCandidate(
            option: CombatSpellOption(
                spell: spell.key,
                cost: Float(spell.cost.cost),
                range: game.magicWorld.castReach(within: spell.data?.range ?? 0),
                chargeSeconds: max(0, spell.data?.chargeTime ?? 0),
                isConcentration: spell.data?.castingType == .concentration
            ),
            isSpell: spell.spellType == .spell,
            targetsSelf: delivery == .selfTarget,
            isDeliverable: SpellDelivery.isImplemented(
                delivery,
                castingType: spell.data?.castingType
            ),
            isHostile: spell.effects.contains {
                $0.effect?.effect.data?.flags.contains(.hostile) == true
            },
            fitsHand: runtime.spellbook.occupancy(of: spell, in: Self.castHand) != nil,
            restoresHealth: spell.effects.contains(where: Self.restoresHealth)
        )
    }

    /// A value modifier on Health that is not detrimental, such as Healing.
    private static func restoresHealth(_ effect: ResolvedSpellEffect) -> Bool {
        guard let data = effect.effect?.effect.data else { return false }
        return data.archetype == .valueModifier
            && data.relatedActorValue == ActorValueIdentity.index(named: "Health")
            && !data.flags.contains(.detrimental) && !data.flags.contains(.hostile)
    }
}
