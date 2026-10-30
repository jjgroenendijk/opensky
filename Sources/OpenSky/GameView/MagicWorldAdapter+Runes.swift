// The rune side of `MagicWorld`: who sets a rune off, who its blast reaches, and the
// `PROJ` explosion a rune sets off. See docs/engine/spell-delivery.md.

import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyWorld

extension MagicWorldAdapter {
    func keyword(editorID: String) -> ReferenceKey? {
        game.worldData?.locationStore?.keywords.keyword(editorID: editorID)
            .map { ReferenceKey(resolved: $0.id) }
    }

    /// The player's runes wait for hostile NPCs; an NPC's rune waits for the player.
    func runeTriggers(for caster: ReferenceKey) -> [MeleeTarget] {
        let living = Set(game.actorWorld.combatActors().filter { !$0.isDead }.map(\.key))
        guard caster != .player else {
            return game.combat.projectileTargets().filter {
                living.contains($0.key) && game.factions.hostility(of: $0.key) == .hostile
            }
        }
        guard game.factions.hostility(of: caster) == .hostile else { return [] }
        return [playerTarget]
    }

    func spellHitCandidates() -> [MeleeTarget] {
        game.combat.projectileTargets() + [playerTarget]
    }

    var isOutdoors: Bool {
        game.streamer.map { !$0.isInterior } ?? false
    }

    func projectileProximity(of payload: SpellPayload) -> Float {
        guard let link = payload.projectile else { return 0 }
        return game.combat.items?.projectileProfile(link)?.explosionProximity ?? 0
    }

    /// The rune's `PROJ` explosion, as a spell projectile's impact sets it off.
    func detonateRune(_ payload: SpellPayload, at position: SIMD3<Float>) {
        let explosions = game.combat.explosions
        guard
            let link = payload.projectile,
            let profile = game.combat.items?.projectileProfile(link),
            let spec = explosions.spec(itemLink: profile.explosion)
        else { return }
        explosions.detonate(spec, at: position, cause: .spell)
    }

    private var playerTarget: MeleeTarget {
        MeleeTarget(key: .player, feet: game.combat.meleeAttacker.feet)
    }
}
