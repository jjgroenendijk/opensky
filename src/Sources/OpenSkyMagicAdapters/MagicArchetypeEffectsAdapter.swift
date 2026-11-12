import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
public import OpenSkyGameData
import OpenSkyMagic
public import OpenSkyMagicInterface
import OpenSkyPlayer
public import OpenSkySessionInterface
import OpenSkyWorld
import simd

/// What `MagicArchetypeEffectsAdapter` reads from the session.
@MainActor
public protocol MagicArchetypeEffectsHost: AnyObject, SendableMetatype {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var controllerRumble: any ControllerRumblePort { get }
    var effectsWorld: any EffectsWorldPort { get }
    var factions: any FactionPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var hud: any HUDPort { get }
    var scripts: any ScriptPort { get }
    var storyWorld: any StoryWorldPort { get }
    var worldRecords: (any WorldRecordsPort)? { get }
}

/// Part of `MagicWorldAdapter`, over its own narrow host.
public struct MagicArchetypeEffectsAdapter {
    public let game: any MagicArchetypeEffectsHost
    public let state: MagicPartState
    let heldMagic: MagicHeldMagicAdapter
    let spellDelivery: MagicSpellDeliveryAdapter
}

extension MagicArchetypeEffectsAdapter {
    public func run(_ commands: [MagicCommand]) {
        for command in commands where !present(command) {
            perform(command)
        }
    }

    /// The commands the player only sees or hears. False for every other command.
    private func present(_ command: MagicCommand) -> Bool {
        switch command {
        case let .castingSound(sound, caster, starts):
            castingSound(sound, caster: caster, starts: starts)
        case let .paintActor(actor, shader, plugin, shown):
            heldMagic.paintActor(actor, shader: shader, plugin: plugin, shown: shown)
        case let .castingArt(art, plugin, caster, starts):
            game.effectsWorld.effects
                .showCastingArt(art, fromPlugin: plugin, on: caster, shown: starts)
        case let .castingLight(light, plugin, caster, starts):
            heldMagic.showCastingLight(light, plugin: plugin, caster: caster, shown: starts)
        case let .spellHit(event): game.effectsWorld.handleSpellHit(event)
        case let .notice(text): game.hud.showNotification(text)
        default: return false
        }
        return true
    }

    private func perform(_ command: MagicCommand) {
        switch command {
        case let .stagger(key, magnitude): staggerActor(key, magnitude: magnitude)
        case let .wardHit(hit, caster, spell):
            game.scripts.runtime?.queueWardHit(
                holder: hit.holder, caster: caster, spell: spell, status: hit.status.rawValue
            )
        case let .spawnHazard(hazard, key): spawnHazard(hazard, at: key)
        case let .playerGrab(body, held): game.scripts.runtime?.queueGrab(of: body, held: held)
        case let .playerGraphEvent(name): game.gameSession?.locomotion.raise(name)
        case let .detonateRune(payload, position): spellDelivery.detonateRune(
                payload,
                at: position
            )
        case let .playerShouted(words):
            game.storyWorld.commentOnPlayer(.playerAction("PCSH"))
            game.controllerRumble.shout(words: words)
        default: break
        }
    }

    /// The player's graph reads the magnitude before the event, as a melee
    /// stagger writes it. An NPC has no graph, so the loop plays its clip.
    @discardableResult
    public func staggerActor(_ key: ReferenceKey, magnitude: Float) -> Bool {
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

    public func cloakTargets(around key: ReferenceKey, radius: Float) -> [ReferenceKey] {
        MagicCloakReach(game: game).cloakTargets(around: key, radius: radius)
    }

    public func knock(
        _ targets: [ReferenceKey],
        awayFrom source: ReferenceKey,
        by payload: SpellPayload
    ) {
        MagicCloakReach(game: game).knock(targets, awayFrom: source, by: payload)
    }

    public func actorHasKeyword(_ editorID: String, on holder: ActorValueHolder) -> Bool {
        keywordChecks.actorHasKeyword(editorID, on: holder)
    }

    public func itemHasKeyword(_ editorID: String, on item: FormID) -> Bool {
        keywordChecks.itemHasKeyword(editorID, on: item)
    }

    /// An item fits when it has a keyword the base's worn restriction list names.
    public func enchantment(_ base: ResolvedEnchantment, fits item: FormID) -> Bool {
        keywordChecks.enchantment(base, fits: item)
    }

    func castingSound(_ sound: FormID, caster: ReferenceKey, starts: Bool) {
        guard let director = game.gameSession?.soundDirector else { return }
        guard starts else {
            director.stopSound(formID: sound, source: caster)
            return
        }
        let combat = game.combat
        let feet = caster == .player
            ? combat.meleeAttacker.feet : combat.combatActor(key: caster)?.feet
        guard let feet else { return }
        director.playSound(formID: sound, source: caster, at: feet)
    }
}

extension MagicArchetypeEffectsAdapter {
    var keywordChecks: MagicKeywordChecks {
        MagicKeywordChecks(game: game, state: state)
    }
}

struct MagicKeywordChecks {
    let game: any MagicArchetypeEffectsHost
    let state: MagicPartState

    func actorHasKeyword(_ editorID: String, on holder: ActorValueHolder) -> Bool {
        guard
            let keywords = game.worldRecords?.locationKeywords,
            let keyword = keywords.keyword(editorID: editorID)?.id,
            let baselines = game.actorValues.runtime
        else { return false }
        var forms = [baselines.baseline(of: holder).race]
        if case let .actor(base) = holder.subject {
            forms.append(base)
        }
        let query = ActorKeywordQuery(keyword: keyword, forms: forms.compactMap(\.self))
        if let known = state.actorKeywordAnswers[query] {
            return known
        }
        let answer = query.forms.contains { form in
            guard let id = keywords.resolvedID(form, fromPlugin: FormIDResolver.loadOrderSpaceName)
            else { return false }
            return keywords.hasKeyword(keyword, on: id) == true
        }
        state.actorKeywordAnswers[query] = answer
        return answer
    }

    func itemHasKeyword(_ editorID: String, on item: FormID) -> Bool {
        guard
            let keywords = game.worldRecords?.locationKeywords,
            let keyword = keywords.keyword(editorID: editorID)?.id,
            let id = keywords.resolvedID(item, fromPlugin: FormIDResolver.loadOrderSpaceName)
        else { return false }
        return keywords.hasKeyword(keyword, on: id) == true
    }

    /// An item fits when it has a keyword the base's worn restriction list names.
    func enchantment(_ base: ResolvedEnchantment, fits item: FormID) -> Bool {
        guard
            let list = base.data?.wornRestrictions,
            let lists = game.worldRecords?.formListStore,
            let keywords = game.worldRecords?.locationKeywords,
            let listID = lists.resolvedID(list, fromPlugin: base.sourcePlugin),
            let id = keywords.resolvedID(item, fromPlugin: FormIDResolver.loadOrderSpaceName)
        else { return true }
        let listed = lists.flattened(listID)?.entries.compactMap(\.self) ?? []
        return listed.isEmpty || listed.contains { keywords.hasKeyword($0, on: id) == true }
    }
}

/// Whom a cloak reaches, and the knock its projectile gives them.
struct MagicCloakReach {
    let game: any MagicArchetypeEffectsHost

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

    /// Knocks each target down, as `PushActorAway` does, at the projectile's push.
    func knock(
        _ targets: [ReferenceKey],
        awayFrom source: ReferenceKey,
        by payload: SpellPayload
    ) {
        guard
            let link = payload.projectile,
            let projectile = game.combat.items?.projectiles[link.rawValue]
        else { return }
        let speed = CloakKnock.speed(
            impactForce: projectile.impactForce,
            bipedMultiplier: game.worldRecords?.gameSettings
                .number("fProjectileKnockMultBiped") ?? 0,
            havokScale: NIFCollisionModel.havokToEngineScale
        )
        guard speed > 0 else { return }
        for target in targets {
            _ = game.effectsWorld.knockDownActor(
                target, awayFrom: source, magnitude: speed / NIFCollisionModel.havokToEngineScale
            )
        }
    }
}
