// The production `PapyrusWorldBridge`: owns the main-actor references natives may not
// hold. The store is strong; the world runtime and `CellStreamer` are weak, because
// they own this bridge or share its owner.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
public import OpenSkyQuestsInterface
public import OpenSkyScriptingInterface
public import OpenSkyWorldInterface
public import OpenSkyWorldState

@MainActor
public final class PapyrusWorldStateBridge: PapyrusWorldBridge {
    public let worldState: WorldStateStore
    /// Set immediately after the world runtime is built — it cannot be an init
    /// parameter, because the runtime is constructed with the native registry
    /// this bridge already lives inside.
    public weak var world: PapyrusWorldRuntime? {
        didSet {
            runState.combatEventKeys = nil
            world?.attachOnUse = { [weak self] in self?.questScripts.attachOnUse($0) ?? false }
            world?.scriptsOfTarget = { [weak self] in self?.questScripts.scriptsOfTarget($0) ?? [] }
            world?
                .isQuestRunning = { [weak self] key in
                    self?.questScripts.isQuestRunning(key) ?? false
                }
        }
    }

    /// Quest mutation API for the `Quest` natives. Nil without QUST data, where they fail
    /// with `PapyrusQuestBridgeError.noQuestData`. See `PapyrusWorldStateBridgeQuests.swift`.
    public var questRuntime: (any QuestAccess)?
    public internal(set) var runState = RunState()
    public var natives = Natives()
    public var stores = Stores()
    /// Master-list resolver for the FormIDs written inside decoded records —
    /// XLKR links and their keywords. Nil in a synthetic session, which falls
    /// back to the reference index.
    public var formIDResolver: FormIDResolver?
    public var ports = Ports()
    private(set) lazy var fragments = Fragments(bridge: self)

    public init(
        worldState: WorldStateStore,
        world: PapyrusWorldRuntime? = nil,
        references: (any PapyrusWorldReferenceSource)? = nil,
        seams: PapyrusBridgeSeams = PapyrusBridgeSeams()
    ) {
        self.worldState = worldState
        self.world = world
        ports.references = references
        questRuntime = seams.quests
        ports.inventory = seams.inventory
        ports.alchemy = seams.alchemy
        ports.actorAI = seams.actorAI
        ports.furniture = seams.furniture
        ports.objectAnimation = seams.objectAnimation
        ports.story = seams.story
        ports.menus = seams.menus
        ports.trapWorld = seams.trapWorld
        ports.presenter = seams.presenter
        stores.itemNotices = seams.itemNotices
        ports.effectPresenter = seams.effectPresenter
        ports.weather = seams.weather
        ports.music = seams.music
    }

    public var playerKey: ReferenceKey {
        .player
    }

    // MARK: - Identity

    public func referenceKey(for handle: PapyrusObjectHandle) -> ReferenceKey? {
        world?.referenceKey(for: handle)
    }

    public func objectHandle(for key: ReferenceKey) -> PapyrusObjectHandle? {
        world?.objectHandle(for: key)
    }

    // MARK: - Reading

    public func triggerObjectCount(for key: ReferenceKey) -> Int {
        runState.triggerOccupants[key]?.count ?? 0
    }

    public func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        ports.references?.cellLocation(of: key)
    }

    // MARK: - Update timers

    public func registerUpdateTimer(
        handle: PapyrusObjectHandle,
        slot: PapyrusUpdateTimerSlot,
        interval: Double
    ) {
        world?.registerUpdateTimer(handle: handle, slot: slot, interval: interval)
    }

    public func unregisterUpdateTimers(
        handle: PapyrusObjectHandle,
        family: PapyrusUpdateTimerFamily
    ) {
        world?.unregisterUpdateTimers(handle: handle, family: family)
    }
}

extension PapyrusWorldStateBridge {
    /// Retires the scripts on the cell's references as the cell leaves the scene.
    public func detachScripts(from cell: CellSceneLocation) {
        world?.detach(cell: cell)
    }
}

extension PapyrusWorldStateBridge {
    /// One frame of world changes turned into script events, in a fixed order: the
    /// journals first, then the timed moves, trigger repeats, and delayed activations.
    public func advanceFrame(by delta: Float) {
        inventoryEvents.queueInventoryEvents()
        effectEvents.queueMagicEffectEvents()
        referenceEvents.queueReferenceStateEvents()
        combatEvents.queueCombatStateEvents()
        trackedStats.queueTrackedStatEvents()
        lineOfSight.queueLineOfSightEvents()
        scriptedMoves.advanceTranslations(by: delta)
        triggers.queueTriggerRepeats(after: delta)
        activationDelays.advanceDelayedActivations(by: delta)
        sunGaze.updateSunGaze()
    }

    /// After a load, the journals start from now, so loaded changes raise no events.
    public func skipJournals() {
        inventoryEvents.skipInventoryJournal()
        effectEvents.skipMagicEffectJournal()
        referenceEvents.skipReferenceStateJournal()
        trackedStats.skipTrackedStatJournal()
        scriptedMoves.clearTranslations()
    }
}

extension PapyrusWorldStateBridge {
    public var activations: Activations {
        Activations(bridge: self)
    }

    var globalReads: Globals {
        Globals(bridge: self)
    }

    var referenceReads: ReferenceReads {
        ReferenceReads(bridge: self)
    }

    var questScripts: QuestScripts {
        QuestScripts(bridge: self)
    }

    var storyEvents: StoryEvents {
        StoryEvents(bridge: self)
    }

    var actorValues: ActorValueCalls {
        ActorValueCalls(bridge: self)
    }

    var spellEffects: SpellEffects {
        SpellEffects(bridge: self)
    }

    var effectEvents: EffectEvents {
        EffectEvents(bridge: self)
    }

    var referenceEvents: ReferenceEvents {
        ReferenceEvents(bridge: self)
    }

    public var referencePlacement: Placements {
        Placements(bridge: self)
    }

    var conditionTwins: ConditionTwins {
        ConditionTwins(bridge: self)
    }

    var inventoryEvents: InventoryEvents {
        InventoryEvents(bridge: self)
    }

    var factions: Factions {
        Factions(bridge: self)
    }

    var guards: Guards {
        Guards(bridge: self)
    }

    var crime: Crime {
        Crime(bridge: self)
    }

    public var scriptState: ScriptState {
        ScriptState(bridge: self)
    }

    var formLists: FormLists {
        FormLists(bridge: self)
    }

    var scriptedMoves: ScriptedMoves {
        ScriptedMoves(bridge: self)
    }

    var sounds: Sounds {
        Sounds(bridge: self)
    }

    public var triggers: Triggers {
        Triggers(bridge: self)
    }

    var trackedStats: TrackedStats {
        TrackedStats(bridge: self)
    }

    var leveledEdits: LeveledEdits {
        LeveledEdits(bridge: self)
    }

    var combatEvents: CombatEvents {
        CombatEvents(bridge: self)
    }

    var itemNoticeLines: ItemNoticeLines {
        ItemNoticeLines(bridge: self)
    }

    var recordReads: RecordReads {
        RecordReads(bridge: self)
    }

    var lineOfSight: LineOfSight {
        LineOfSight(bridge: self)
    }

    var sunGaze: SunGaze {
        SunGaze(bridge: self)
    }

    public var stateLinks: StateLinks {
        StateLinks(bridge: self)
    }

    var referenceRules: ReferenceRules {
        ReferenceRules(bridge: self)
    }

    var activationDelays: ActivationDelays {
        ActivationDelays(bridge: self)
    }

    public struct Activations {
        let bridge: PapyrusWorldStateBridge
    }

    struct Globals {
        let bridge: PapyrusWorldStateBridge
    }

    struct ReferenceReads {
        let bridge: PapyrusWorldStateBridge
    }

    /// Quest stages, aliases, objectives, and the scripts a quest attaches.
    struct QuestScripts: Sendable {
        let bridge: PapyrusWorldStateBridge
    }

    /// Story manager starts and the package and perk fragments they run.
    struct StoryEvents {
        let bridge: PapyrusWorldStateBridge
    }

    /// Actor values, death, and the actor flags scripts change.
    struct ActorValueCalls: Sendable {
        let bridge: PapyrusWorldStateBridge
    }

    /// Spells, active effects, and casting for the magic natives.
    struct SpellEffects: Sendable {
        let bridge: PapyrusWorldStateBridge
    }

    /// The magic effect events queued from the effect journal.
    struct EffectEvents {
        let bridge: PapyrusWorldStateBridge
    }

    /// The reference state events queued from the journal, and destruction.
    struct ReferenceEvents {
        let bridge: PapyrusWorldStateBridge
    }

    /// Placing, moving, and spawning references.
    public struct Placements {
        let bridge: PapyrusWorldStateBridge
    }

    /// Natives that answer through a condition function.
    struct ConditionTwins {
        let bridge: PapyrusWorldStateBridge
    }

    /// The inventory events queued from the journal, and their filters.
    struct InventoryEvents {
        let bridge: PapyrusWorldStateBridge
    }

    /// Faction membership, ranks, and reactions.
    struct Factions: Sendable {
        let bridge: PapyrusWorldStateBridge
    }

    /// Guards recognising the player and arrests.
    struct Guards: Sendable {
        let bridge: PapyrusWorldStateBridge
    }

    /// Crimes, bounties, and ownership.
    struct Crime: Sendable {
        let bridge: PapyrusWorldStateBridge
    }

    /// The state scripts keep on references, and the equipped shout.
    public struct ScriptState {
        let bridge: PapyrusWorldStateBridge
    }

    /// Form lists and keywords.
    struct FormLists {
        let bridge: PapyrusWorldStateBridge
    }

    /// Scripted moves in progress, such as TranslateTo.
    struct ScriptedMoves {
        let bridge: PapyrusWorldStateBridge
    }

    /// Latent sound waits.
    struct Sounds {
        let bridge: PapyrusWorldStateBridge
    }

    /// Trigger volumes and who stands in them.
    public struct Triggers {
        let bridge: PapyrusWorldStateBridge
    }

    /// The tracked stats events queued from the journal.
    struct TrackedStats {
        let bridge: PapyrusWorldStateBridge
    }

    /// Script edits to leveled lists.
    struct LeveledEdits {
        let bridge: PapyrusWorldStateBridge
    }

    /// Combat state changes and the actor combat reads.
    struct CombatEvents {
        let bridge: PapyrusWorldStateBridge
    }

    /// The added and removed item notices.
    struct ItemNoticeLines {
        let bridge: PapyrusWorldStateBridge
    }

    /// Record reads and script hit events.
    struct RecordReads {
        let bridge: PapyrusWorldStateBridge
    }

    /// Line of sight between references.
    struct LineOfSight {
        let bridge: PapyrusWorldStateBridge
    }

    /// The sun gaze image-space modifier.
    struct SunGaze {
        let bridge: PapyrusWorldStateBridge
    }

    /// Player controls and the links scripts keep between references.
    public struct StateLinks {
        let bridge: PapyrusWorldStateBridge
    }

    /// Reference rules: distance, angle, and motion.
    struct ReferenceRules {
        let bridge: PapyrusWorldStateBridge
    }

    /// Activate children waiting out their delay.
    struct ActivationDelays {
        let bridge: PapyrusWorldStateBridge
    }
}

extension PapyrusWorldStateBridge {
    /// The host's native hooks, one table per area.
    public struct Natives {
        public var faction = PapyrusFactionNatives()
        public var actor = PapyrusActorNatives()
        public var magic = PapyrusMagicNatives()
        public var progression = PapyrusProgressionNatives()
        public var crime = PapyrusCrimeNatives()
        public var player = PapyrusPlayerNatives()
        public var perception = PapyrusPerceptionNatives()
        public var session = PapyrusSessionNatives()
        public var story = PapyrusStoryNatives()
        public var game = PapyrusGameNatives()
    }

    /// The record stores the natives read. Each is nil in a synthetic session.
    public struct Stores {
        /// Plugin GLOB defaults. Nil in a synthetic session, where only overrides
        /// already recorded in the store are visible.
        public var globals: GlobalStore?
        /// Load-order MGEF lookup, for `HasMagicEffectWithKeyword`. Nil in a
        /// synthetic session with no record index.
        public var magicEffectStore: MagicEffectStore?
        /// Load-order FLST lookup, for the `FormList` natives. Nil fails them.
        public var formListStore: FormListStore?
        /// Load-order KYWD and `KWDA` lookup, for `HasKeyword`. Nil fails it.
        public var keywordStore: KeywordStore?
        /// Lazily built reverse map for the global lookups, which are keyed by
        /// `ReferenceKey` on the Papyrus side and by `FormID` on the store side.
        var globalFormIDsByKey: [ReferenceKey: FormID]?
        /// The words of the item notices, such as "added".
        public var itemNotices = ItemNoticeTexts()
    }

    /// The host systems the natives call. Weak, because the session owns them.
    public struct Ports {
        public weak var references: (any PapyrusWorldReferenceSource)?
        /// The story manager and scenes, for the `Keyword` and `Scene` natives.
        public weak var story: (any PapyrusStoryBridge)?
        /// The race menu, map markers, fast travel, and the player's identity.
        public weak var menus: (any PapyrusMenuBridge)?
        /// Hazards and explosions that `PlaceAtMe` places.
        public weak var trapWorld: (any PapyrusTrapWorldBridge)?
        /// Object behaviour graphs, for the animation natives. Nil paces them.
        public weak var objectAnimation: (any PapyrusObjectAnimationBridge)?
        /// Notifications, message boxes, and camera effects. Nil in a headless session.
        public weak var presenter: (any PapyrusPresenting)?
        /// Visual effects, effect shaders, and image-space modifiers. Nil in a headless session.
        public weak var effectPresenter: (any PapyrusEffectPresenting)?
        /// The sky, for the `Weather` natives. Nil in a headless session.
        public weak var weather: (any PapyrusWeatherControlling)?
        public weak var music: (any PapyrusMusicControlling)?
        /// Packages, vehicles, and idles for the actor AI natives.
        public weak var actorAI: (any PapyrusActorAIBridge)?
        /// Furniture seats, for `IsFurnitureInUse` and `SetSittingRotation`.
        public weak var furniture: (any PapyrusFurnitureBridge)?
        /// Inventories and equipment, for the item natives.
        public weak var inventory: (any PapyrusInventoryBridge)?
        /// Ingredient knowledge, for the `Ingredient` and `Potion` natives.
        public weak var alchemy: (any PapyrusAlchemyBridge)?
    }
}

extension PapyrusWorldStateBridge {
    /// What the parts keep between frames: journal cursors, trigger occupants,
    /// delayed activations, and moves in progress.
    public struct RunState {
        /// Quests whose alias fill failed while scripts were attached at wire-up. Counted,
        /// not thrown: a quest running from its DNAM flag has no `Start` call to refuse.
        public var questAliasFillFailures = 0
        /// Who stands in each trigger volume, kept from the enter and leave events.
        public var triggerOccupants: [ReferenceKey: Set<ReferenceKey>] = [:]
        /// Seconds since the last `OnTrigger` repeat.
        public var triggerRepeatElapsed: Float = 0
        /// Activate children still waiting out their `XAPR` delay, in the order they were queued.
        public var delayedActivations: [DelayedActivation] = []
        /// The actor `KillSilent` is killing, so the host skips the story-manager `KILL` event.
        public var silentDeath: ReferenceKey?
        /// The first journal entry `queueInventoryEvents` has not read; nil before its first call.
        public var inventoryJournalCursor: UInt64?
        /// The next `Sound.PlayAndWait` token.
        public var latentWaitToken = PapyrusWorldStateBridge.Sounds.firstLatentWaitToken
        /// Holders a script equipped or unequipped since the last `queueInventoryEvents`.
        public var scriptedEquipHolders: Set<ReferenceKey> = []
        /// The first journal entry `queueMagicEffectEvents` has not read; nil before its first
        /// call.
        public var effectJournalCursor: UInt64?
        /// The first journal entry `queueReferenceStateEvents` has not read.
        public var referenceJournalCursor: UInt64?
        public var statsJournalCursor: UInt64?
        /// Each scripted actor's combat activity at the last `queueCombatStateEvents`.
        var lastCombatActivity: [ReferenceKey: ActorCombatActivity] = [:]
        /// The instances with an `OnCombatStateChanged`, sorted, at one instance revision.
        var combatEventKeys: (revision: UInt64, keys: [PapyrusInstanceKey])?
        /// `Game.SetSunGazeImageSpaceModifier`'s modifier, or nil for none.
        public var sunGazeModifier: ReferenceKey?
        public var wasSunGazing = false
        /// Scripted moves in progress. See `PapyrusWorldTranslations.swift`.
        public var translations: [ReferenceKey: PapyrusTranslation] = [:]
    }
}
