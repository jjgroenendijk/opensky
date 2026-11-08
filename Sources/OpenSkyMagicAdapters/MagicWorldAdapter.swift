// App side of `MagicCoordinator`: builds its runtimes from the provider, steps
// them from the renderer's frame hooks, and answers `MagicWorld` from the
// session systems. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyActors
import OpenSkyActorsInterface
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFactions
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
public import OpenSkyMagic
public import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
public import OpenSkyWorldState

/// What `MagicWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol MagicWorldHost: AnyObject {
    var actorValues: any ActorValuePort { get }
    var inventoryWorld: any InventoryWorldPort { get }
    var combat: any CombatPort { get }
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var mapWorld: any MapWorldPort { get }
    var mountWorld: any MountWorldPort { get }
    var perks: any PerkPort { get }
    var scripts: any ScriptPort { get }
}

/// Answers `MagicWorld` from the session systems `game` owns.
public final class MagicWorldAdapter {
    public unowned let game: any MagicWorldHost
    /// The NPCs a Grab Actor effect holds through the ridden-actor hold.
    public var grabbedActors: Set<ReferenceKey> = []
    /// The `MGEF` casting light each readying caster shows, by caster.
    public var castingLights: [ReferenceKey: ReferenceKey] = [:]
    /// Race and base keywords never change in a session, and a lookup decodes the record.
    public var actorKeywordAnswers: [ActorKeywordQuery: Bool] = [:]

    public let archetypeEffectsHost: any MagicArchetypeEffectsHost
    public let spellDeliveryHost: any MagicSpellDeliveryHost
    public let heldMagicHost: any MagicHeldMagicHost
    public let summonedActorsHost: any MagicSummonedActorsHost
    public let worldFactsHost: any MagicWorldFactsHost

    public var archetypeEffects: MagicArchetypeEffectsAdapter {
        MagicArchetypeEffectsAdapter(
            owner: self,
            game: archetypeEffectsHost
        )
    }

    public var spellDelivery: MagicSpellDeliveryAdapter {
        MagicSpellDeliveryAdapter(
            owner: self,
            game: spellDeliveryHost
        )
    }

    public var heldMagic: MagicHeldMagicAdapter {
        MagicHeldMagicAdapter(owner: self, game: heldMagicHost)
    }

    public var summonedActors: MagicSummonedActorsAdapter {
        MagicSummonedActorsAdapter(
            owner: self,
            game: summonedActorsHost
        )
    }

    public var worldFacts: MagicWorldFactsAdapter {
        MagicWorldFactsAdapter(
            owner: self,
            game: worldFactsHost
        )
    }

    public init(game: some MagicWorldHost & MagicArchetypeEffectsHost & MagicSpellDeliveryHost &
        MagicHeldMagicHost & MagicSummonedActorsHost & MagicWorldFactsHost)
    {
        archetypeEffectsHost = game
        spellDeliveryHost = game
        heldMagicHost = game
        summonedActorsHost = game
        worldFactsHost = game
        self.game = game
    }

    /// After `wireActorValues`, because every effect writes an actor value, and after
    /// `wireWorldItems`, because the spellbook reads the equipment.
    public func wireMagic(gameSession: GameSession) {
        let coordinator = game.magic
        // `Mod Spell Cost` folds through the caster's own copy of the perks.
        coordinator.caster?.perks = game.perks.runtime
        if coordinator.effects != nil {
            registerEffects(coordinator, gameSession: gameSession)
        }
        if coordinator.caster != nil {
            registerCasting(coordinator, gameSession: gameSession)
        }
    }

    public func sessionData(
        provider: WorldDataStores,
        store worldState: WorldStateStore
    ) -> MagicSessionData {
        let settings = provider.gameSettings
        var data = MagicSessionData()
        if
            let values = game.actorValues.runtime,
            let store = provider.magicEffectStore,
            let pluginName = provider.magicItemPluginName
        {
            data.effects = MagicEffectsData(
                values: values, store: store, pluginName: pluginName, conditionRegistry: .standard
            )
        }
        if
            let values = game.actorValues.runtime,
            let spells = provider.spellStore,
            let equipSlots = provider.equipSlotStore
        {
            data.casting = MagicCastingData(
                spellbook: SpellbookRuntime(
                    store: worldState,
                    spells: spells,
                    equipSlots: equipSlots,
                    equipment: game.inventory.equipment
                ),
                values: values,
                spellPluginName: provider.magicItemPluginName,
                baselines: provider.actorValueBaselines?.resolver
                    .map { ActorSpellBaselineResolver(actorValues: $0) }
            )
        }
        data.enchantments = provider.enchantmentStore
        data.shouts = provider.shoutStore
        data.rules.spellCost = SpellCostSettings.resolve(store: settings)
        data.rules.soulTrap = SoulTrapSettings.resolve(store: settings)
        data.rules.holds = MagicHoldSettings.resolve(store: settings)
        data.rules.enchanting = EnchantingSettings.resolve(store: settings)
        data.rules.shouts = ShoutSettings.resolve(store: settings)
        data.rules.runes = RuneSettings.resolve(store: settings)
        data.rules.summons = SummonSettings.resolve(store: settings)
        data.rules.world = MagicWorldSettings.resolve(store: settings)
        data.texts.magic = MagicTexts.resolve(store: settings) { [game] in game.mapWorld.text($0) }
        data.texts.castNotices = game.mapWorld.settingTexts()
        data.texts.souls = SoulTexts.resolve(store: settings) { [game] in game.mapWorld.text($0) }
        return data
    }

    /// Chained after regeneration and the Papyrus VM, on the same delta.
    private func registerEffects(_ coordinator: any MagicPort, gameSession: GameSession) {
        let worldTick = gameSession.worldTick
        worldTick.register(.magicEffects) { [weak self, weak coordinator, weak gameSession] delta in
            self?.archetypeEffects.run(coordinator?.advanceEffects(delta: delta) ?? [])
            self?.heldMagic.publishMagicLights()
            self?.heldMagic.publishSummonFades()
            gameSession?.isPlayerParalysed = coordinator?.influence(of: .player)
                .isParalysed ?? false
            let scales = coordinator?.timeScales ?? .normal
            gameSession?.magicTimeScale = scales.world
            gameSession?.playerTimeScale = scales.player
        }
    }

    /// A frame step, beside melee: a cast is timed against the rendered frame.
    private func registerCasting(_ coordinator: any MagicPort, gameSession: GameSession) {
        let frameSteps = gameSession.frameSteps
        frameSteps.register(.spellCasting) { [weak self, weak coordinator, weak gameSession] _ in
            guard let coordinator, let gameSession else { return }
            let locomotion = gameSession.locomotion
            let isPlayerControlled = gameSession.movementMode.isPlayerControlled
            let delta = locomotion.archeryIntent.deltaTime
            let events = locomotion.graphEvents.drain(locomotion.magicEventConsumer)
            let commands = coordinator.advanceCasting(
                CastingIntent(
                    leftHeld: locomotion.meleeIntent.block,
                    rightHeld: locomotion.archeryIntent.drawing,
                    deltaTime: delta
                ),
                isPlayerControlled: isPlayerControlled,
                events: events,
                weaponsDrawn: self?.game.combat.melee?.state.drawState.isWeaponInHand
            )
            self?.archetypeEffects.run(commands)
            self?.archetypeEffects.run(coordinator.advanceShout(
                held: locomotion.isShoutHeld,
                delta: delta,
                events: events,
                isPlayerControlled: isPlayerControlled
            ))
        }
    }

    /// A hit from outside the magic frame steps runs its commands at once, so the
    /// hit effects and the ragdoll's push land in the same frame as the damage.
    @discardableResult
    public func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        let report = game.magic.applySpellHit(hit)
        archetypeEffects.run(game.magic.takeCommands())
        return report
    }

    public func noteSpellCast(_ spell: ReferenceKey, by caster: ReferenceKey) {
        game.scripts.runtime?.queueSpellCast(spell, by: caster)
    }

    /// Only the player rides.
    public func isOnFlyingMount(_ key: ReferenceKey) -> Bool {
        key == .player && !game.mountWorld.flyingMounts.isEmpty
    }

    public func forgetPickpocketCatch(of key: ReferenceKey) {
        game.inventoryWorld.forgetPickpocketCatch(of: key)
    }
}

extension MagicWorldAdapter: MagicWorld {}
extension MagicWorldAdapter: SpellHitApplying {}

/// One keyword asked of an actor's race and base form.
public struct ActorKeywordQuery: Hashable {
    public let keyword: ResolvedFormID
    public let forms: [FormID]
}

extension MagicWorldAdapter: MagicWorldPort {}
