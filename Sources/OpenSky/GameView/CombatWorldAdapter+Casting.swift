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

    /// Grants the authored spell list on first ask, so townsfolk who never
    /// fight write no spellbook into the save.
    func castingFacts(of key: ReferenceKey) -> CombatCastingFacts? {
        guard
            let runtime = game.casting.runtime,
            let values = game.actorValues.runtime,
            let holder = game.actorValueHolder(for: key)
        else { return nil }
        grantActorSpells(to: holder)
        return CombatCastingFacts(
            magicka: values.current(of: holder).magicka,
            spells: runtime.spellbook.knownSpells(of: holder)
                .map { candidate($0, runtime: runtime) }
        )
    }

    @discardableResult
    func beginCast(_ spell: ReferenceKey, by key: ReferenceKey) -> Bool {
        guard
            let runtime = game.casting.runtime,
            let holder = game.actorValueHolder(for: key),
            (try? runtime.spellbook.equip(spell, in: Self.castHand, on: holder)) != nil
        else { return false }
        return runtime.begin(Self.castHand, on: holder).failure == nil
    }

    /// A maintained cast under its SPIT minimum keeps running after release.
    /// An NPC has no button still held, so that cast is dropped instead.
    @discardableResult
    func releaseCast(by key: ReferenceKey) -> Bool {
        guard let runtime = game.casting.runtime, let holder = game.actorValueHolder(for: key)
        else { return false }
        let outcome = runtime.release(Self.castHand, on: holder)
        if runtime.phase(of: Self.castHand, on: key).isCasting {
            runtime.cancel(Self.castHand, on: holder)
        }
        return outcome.isFinished
    }

    func cancelCast(by key: ReferenceKey) {
        guard let runtime = game.casting.runtime, let holder = game.actorValueHolder(for: key)
        else { return }
        runtime.cancel(Self.castHand, on: holder)
    }

    private func grantActorSpells(to holder: ActorValueHolder) {
        guard
            let runtime = game.casting.runtime,
            let resolver = game.casting.spellBaselines,
            let plugin = game.casting.spellPluginName,
            !game.casting.grantedActors.contains(holder.key)
        else { return }
        game.casting.grantedActors.insert(holder.key)
        let baseline = resolver.baseline(for: holder.subject)
        runtime.spellbook.grant(
            runtime.spellbook.resolve(baseline.all, fromPlugin: plugin),
            to: holder
        )
        runtime.applyAbilities(on: holder)
    }

    private func candidate(_ spell: ResolvedSpell, runtime: CasterRuntime) -> CombatSpellCandidate {
        let delivery = spell.data?.delivery ?? .selfTarget
        return CombatSpellCandidate(
            option: CombatSpellOption(
                spell: spell.key,
                cost: Float(spell.cost.cost),
                range: game.castReach(within: spell.data?.range ?? 0),
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
            fitsHand: runtime.spellbook.occupancy(of: spell, in: Self.castHand) != nil
        )
    }
}
