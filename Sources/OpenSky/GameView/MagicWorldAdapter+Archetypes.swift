// The world half of the magic archetypes: stagger through the combat loop, hazards
// through the trap bridge, cloak targets from the resident actors, and actor
// keywords from the base record and the race (docs/engine/magic-archetypes.md).

import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombat
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyPlayer
import OpenSkyWorld
import simd

extension MagicWorldAdapter {
    func run(_ commands: [MagicCommand]) {
        for command in commands {
            switch command {
            case let .stagger(key, magnitude): staggerActor(key, magnitude: magnitude)
            case let .spawnHazard(hazard, key): spawnHazard(hazard, at: key)
            case let .playerGraphEvent(name): game.gameSession?.locomotion.raise(name)
            }
        }
    }

    /// The player's graph reads the magnitude before the event, as a melee
    /// stagger writes it. An NPC has no graph, so the loop plays its clip.
    @discardableResult
    func staggerActor(_ key: ReferenceKey, magnitude: Float) -> Bool {
        let combat = game.combat
        guard key != .player else {
            combat.writeCombatVariable(.real(magnitude), named: CombatGraphNames.staggerMagnitude)
            return combat.raiseCombatEvent(CombatGraphNames.staggerStart, on: nil)
        }
        guard let loop = combat.loop else { return false }
        loop.noteStagger(of: key)
        return true
    }

    @discardableResult
    func spawnHazard(_ hazard: ReferenceKey, at key: ReferenceKey) -> Bool {
        game.effectsWorld.placeAtMe(hazard, at: key, count: 1) != nil
    }

    /// Cloak spells "will not damage followers or friendly NPCs, only ones who are
    /// hostile to you" (<https://en.uesp.net/wiki/Skyrim:Cloak>). An NPC's cloak
    /// reaches only the player, the one target an NPC fights.
    func cloakTargets(around key: ReferenceKey, radius: Float) -> [ReferenceKey] {
        let living = game.actorWorld.combatActors().filter { !$0.isDead }
        let playerFeet = game.combat.meleeAttacker.feet
        guard key != .player else {
            return living
                .filter { simd_distance($0.feet, playerFeet) <= radius }
                .filter { game.factions.hostility(of: $0.key) == .hostile }
                .map(\.key)
        }
        guard
            let caster = living.first(where: { $0.key == key }),
            game.factions.hostility(of: key) == .hostile,
            simd_distance(caster.feet, playerFeet) <= radius
        else { return [] }
        return [.player]
    }

    func actorHasKeyword(_ editorID: String, on holder: ActorValueHolder) -> Bool {
        guard
            let keywords = game.worldData?.locationStore?.keywords,
            let keyword = keywords.keyword(editorID: editorID)?.id,
            let baselines = game.actorValues.runtime
        else { return false }
        var forms = [baselines.baseline(of: holder).race]
        if case let .actor(base) = holder.subject {
            forms.append(base)
        }
        return forms.compactMap(\.self).contains { form in
            guard let id = keywords.resolvedID(form, fromPlugin: FormIDResolver.loadOrderSpaceName)
            else { return false }
            return keywords.hasKeyword(keyword, on: id) == true
        }
    }

    func itemHasKeyword(_ editorID: String, on item: FormID) -> Bool {
        guard
            let keywords = game.worldData?.locationStore?.keywords,
            let keyword = keywords.keyword(editorID: editorID)?.id,
            let id = keywords.resolvedID(item, fromPlugin: FormIDResolver.loadOrderSpaceName)
        else { return false }
        return keywords.hasKeyword(keyword, on: id) == true
    }

    /// An item fits when it has a keyword the base's worn restriction list names.
    func enchantment(_ base: ResolvedEnchantment, fits item: FormID) -> Bool {
        guard
            let list = base.data?.wornRestrictions,
            let lists = game.worldData?.formListStore,
            let keywords = game.worldData?.locationStore?.keywords,
            let listID = lists.resolvedID(list, fromPlugin: base.sourcePlugin),
            let id = keywords.resolvedID(item, fromPlugin: FormIDResolver.loadOrderSpaceName)
        else { return true }
        let listed = lists.flattened(listID)?.entries.compactMap(\.self) ?? []
        return listed.isEmpty || listed.contains { keywords.hasKeyword($0, on: id) == true }
    }
}
