// App side of `MagicCoordinator`: builds its runtimes from the provider, steps
// them from the renderer's frame hooks, and answers `MagicWorld` from the
// session systems. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyActorsInterface
public import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMagic
public import OpenSkyMagicInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
public import OpenSkyWorldState

/// What `MagicWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol MagicWorldHost: AnyObject, SendableMetatype {
    var actorValues: any ActorValuePort { get }
    var inventoryWorld: any InventoryWorldPort { get }
    var combat: any CombatPort { get }
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var mapWorld: any MapWorldPort { get }
    var mountWorld: any MountWorldPort { get }
    var scripts: any ScriptPort { get }
}

/// Answers `MagicWorld` from the session systems `game` owns.
/// Every host a `MagicWorldAdapter` part reads, all one object.
public typealias MagicWorldHosts = MagicArchetypeEffectsHost & MagicHeldMagicHost &
    MagicSpellDeliveryHost & MagicSummonedActorsHost & MagicWorldFactsHost & MagicWorldHost

public final class MagicWorldAdapter {
    public let game: any MagicWorldHost
    let state = MagicPartState()

    let frames: MagicFrameSteps

    public var archetypeEffects: MagicArchetypeEffectsAdapter {
        frames.archetypeEffects
    }

    public var spellDelivery: MagicSpellDeliveryAdapter {
        frames.spellDelivery
    }

    public var heldMagic: MagicHeldMagicAdapter {
        frames.heldMagic
    }

    public var summonedActors: MagicSummonedActorsAdapter {
        frames.summonedActors
    }

    public var worldFacts: MagicWorldFactsAdapter {
        frames.worldFacts
    }

    /// Builds the session's magic runtimes, rules, and texts from the loaded data.
    public var sessions: MagicSessionBuilder {
        MagicSessionBuilder(game: game)
    }

    public init(game: some MagicWorldHosts) {
        self.game = game
        frames = MagicFrameSteps(hosts: game, state: state)
    }

    /// A hit from outside the magic frame steps runs its commands at once, so the
    /// hit effects and the ragdoll's push land in the same frame as the damage.
    @discardableResult
    public func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        let report = game.magic.applySpellHit(hit)
        archetypeEffects.run(game.magic.frameStep.takeCommands())
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

/// Builds the magic session data from the loaded data stores.
public struct MagicSessionBuilder {
    let game: any MagicWorldHost

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
            let spells = provider.progression.spellStore,
            let equipSlots = provider.progression.equipSlotStore
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
        data.enchantments = provider.progression.enchantmentStore
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
}

/// The magic parts over one host, and the frame steps that advance effects and casting.
final class MagicFrameSteps {
    let hosts: any MagicWorldHosts
    let state: MagicPartState

    init(hosts: any MagicWorldHosts, state: MagicPartState) {
        self.hosts = hosts
        self.state = state
    }

    var game: any MagicWorldHost {
        hosts
    }

    var archetypeEffects: MagicArchetypeEffectsAdapter {
        MagicArchetypeEffectsAdapter(
            game: hosts, state: state, heldMagic: heldMagic,
            spellDelivery: spellDelivery
        )
    }

    var spellDelivery: MagicSpellDeliveryAdapter {
        MagicSpellDeliveryAdapter(game: hosts
        )
    }

    var heldMagic: MagicHeldMagicAdapter {
        MagicHeldMagicAdapter(
            game: hosts, state: state, summonedActors: summonedActors,
            spellDelivery: spellDelivery
        )
    }

    var summonedActors: MagicSummonedActorsAdapter {
        MagicSummonedActorsAdapter(game: hosts
        )
    }

    var worldFacts: MagicWorldFactsAdapter {
        MagicWorldFactsAdapter(game: hosts
        )
    }

    /// Chained after regeneration and the Papyrus VM, on the same delta.
    func registerEffects(gameSession: GameSession) {
        let worldTick = gameSession.worldTick
        worldTick.register(.magicEffects) { [weak self, weak gameSession] delta in
            let coordinator = self?.game.magic
            guard coordinator?.effects != nil else { return }
            self?.archetypeEffects.run(coordinator?.frameStep.advanceEffects(delta: delta) ?? [])
            self?.heldMagic.publishMagicLights()
            self?.heldMagic.publishSummonFades()
            gameSession?.motion.isPlayerParalysed = coordinator?.archetypeActions
                .influence(of: .player)
                .isParalysed ?? false
            let scales = coordinator?.timeScales ?? .normal
            gameSession?.magicTimeScale = scales.world
            gameSession?.playerTimeScale = scales.player
        }
    }

    /// A frame step, beside melee: a cast is timed against the rendered frame.
    func registerCasting(gameSession: GameSession) {
        let frameSteps = gameSession.frameSteps
        frameSteps.register(.spellCasting) { [weak self, weak gameSession] _ in
            guard let coordinator = self?.game.magic, coordinator.caster != nil, let gameSession
            else { return }
            let locomotion = gameSession.locomotion
            let isPlayerControlled = gameSession.movementMode.isPlayerControlled
            let delta = locomotion.archeryIntent.deltaTime
            let events = locomotion.graphEvents.drain(locomotion.magicEventConsumer)
            let commands = coordinator.frameStep.advanceCasting(
                CastingIntent(
                    leftHeld: locomotion.meleeIntent.block,
                    rightHeld: locomotion.archeryIntent.drawing,
                    deltaTime: delta
                ),
                isPlayerControlled: isPlayerControlled,
                events: events,
                weaponsDrawn: self?.game.combat.meleeWeaponInHand
            )
            self?.archetypeEffects.run(commands)
            self?.archetypeEffects.run(coordinator.shoutVoice.advanceShout(
                held: locomotion.isShoutHeld,
                delta: delta,
                events: events,
                isPlayerControlled: isPlayerControlled
            ))
        }
    }
}
