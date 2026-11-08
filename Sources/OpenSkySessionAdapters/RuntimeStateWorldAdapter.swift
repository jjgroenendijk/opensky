// App side of `RuntimeStateCoordinator`: answers `RuntimeStateWorld` from the
// renderer, the streamer, and the session systems, and runs save and load.
// The rules live in the coordinator (docs/engine/coordinators.md).

import Foundation
import OpenSkyActorPresentation
import OpenSkyActors
public import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyAudio
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
public import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyFactions
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkyRuntimeState
public import OpenSkySave
import OpenSkySaveInterface
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldConditions
public import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `RuntimeStateWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol RuntimeStateWorldHost: AnyObject {
    var dragonFlightWorld: any DragonFlightWorldPort { get }
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var idleWorld: any IdleWorldPort { get }
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

public final class RuntimeStateWorldAdapter {
    public unowned let game: any RuntimeStateWorldHost
    /// Resolved once: retrying an unwritable Application Support on every
    /// readout tick would hit the disk for the same answer.
    private var saveStore: OpenSkySaveStore?
    /// Parses every plugin header, so it is built once per session.
    private var fingerprint: Task<[SavePluginFingerprint], any Error>?
    /// Built once, the first time a condition asks where something is.
    private var cellLocations: CellLocationResolver?
    /// Reference places for one set of resident cells, rebuilt when the set changes.
    private var referencePlaces: ResidentReferencePlaces?
    /// Condition views kept until their inputs change.
    public let conditionCaches = ConditionViewCaches()

    public let sessionClockHost: any RuntimeStateSessionClockHost
    public let conditionReadsHost: any RuntimeStateConditionReadsHost
    public let saveContentsHost: any RuntimeStateSaveContentsHost
    public let sessionLoadHost: any RuntimeStateSessionLoadHost
    public let liveSeamsHost: any RuntimeStateLiveSeamsHost
    public let referenceMotionHost: any RuntimeStateReferenceMotionHost
    public let inventoryFactsHost: any RuntimeStateInventoryFactsHost

    public var sessionClock: RuntimeStateSessionClockAdapter {
        RuntimeStateSessionClockAdapter(
            owner: self,
            game: sessionClockHost
        )
    }

    public var conditionReads: RuntimeStateConditionReadsAdapter {
        RuntimeStateConditionReadsAdapter(
            owner: self,
            game: conditionReadsHost
        )
    }

    public var saveContents: RuntimeStateSaveContentsAdapter {
        RuntimeStateSaveContentsAdapter(
            owner: self,
            game: saveContentsHost
        )
    }

    public var sessionLoad: RuntimeStateSessionLoadAdapter {
        RuntimeStateSessionLoadAdapter(
            owner: self,
            game: sessionLoadHost
        )
    }

    public var liveSeams: RuntimeStateLiveSeamsAdapter {
        RuntimeStateLiveSeamsAdapter(
            owner: self,
            game: liveSeamsHost
        )
    }

    public var referenceMotion: RuntimeStateReferenceMotionAdapter {
        RuntimeStateReferenceMotionAdapter(
            owner: self,
            game: referenceMotionHost
        )
    }

    public var inventoryFacts: RuntimeStateInventoryFactsAdapter {
        RuntimeStateInventoryFactsAdapter(
            owner: self,
            game: inventoryFactsHost
        )
    }

    public init(game: some RuntimeStateWorldHost & RuntimeStateSessionClockHost &
        RuntimeStateConditionReadsHost & RuntimeStateSaveContentsHost &
        RuntimeStateSessionLoadHost &
        RuntimeStateLiveSeamsHost & RuntimeStateReferenceMotionHost &
        RuntimeStateInventoryFactsHost)
    {
        sessionClockHost = game
        conditionReadsHost = game
        saveContentsHost = game
        sessionLoadHost = game
        liveSeamsHost = game
        referenceMotionHost = game
        inventoryFactsHost = game
        self.game = game
    }

    public static var saveAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
    }

    /// Every resident actor plus the player, with the combat loop's fight
    /// filled in both directions.
    public func actorResolution() -> ActorStateResolution {
        guard let values = game.actorValues.runtime else { return .empty }
        var player = actorConditionState(holder: .player, values: values)
        inventoryFacts.playerConditionTraits(&player)
        var states = residentActorStates(values: values)
        states[.player] = player
        return ActorStateResolution.fight(
            states: states, playerKey: .player, playerTarget: game.combat.loop?.state.target
        )
    }

    /// Actor values, death and equipment are store writes; the fight is each machine's phase.
    private func residentActorStates(values: any ActorValueRuntimePort)
        -> [ReferenceKey: ActorConditionState]
    {
        let members = game.actorWorld.combatActors().compactMap { observation in
            game.actorWorld.actorValueHolder(for: observation.key).map {
                ActorViewMember(holder: $0, isDead: observation.isDead)
            }
        }
        let key = ActorViewKey(
            store: ObjectIdentifier(game.worldState),
            writes: game.worldState.revision(of: [.actorValues, .inventory]),
            playerLevel: values.baselines.playerLevel.level,
            hasInventory: game.inventory.equipment != nil,
            actors: members,
            phases: game.combat.loop?.behaviors.mapValues(\.phase)
        )
        return conditionCaches.actors.value(for: key) {
            members.reduce(into: [:]) { states, member in
                states[member.holder.key] = actorConditionState(
                    holder: member.holder, values: values, isDead: member.isDead
                )
            }
        }
    }

    /// Only the player has a graph that tracks a draw state, so every other
    /// actor carries nil and `IsWeaponOut` reports the gap. OpenSky draws no
    /// torch, and a shield comes out only with a drawn weapon, so a sheathed or
    /// peaceful actor holds nothing out.
    private func actorConditionState(
        holder: ActorValueHolder,
        values: any ActorValueRuntimePort,
        isDead: Bool = false
    ) -> ActorConditionState {
        let baseline = values.baseline(of: holder)
        let activity = game.combat.loop?.activity(of: holder.key) ?? .notFighting
        let drawState = holder.key == .player ? game.combat.melee?.state.drawState : nil
        let handIsEmpty = drawState.map { !$0.isWeaponInHand } ?? (activity == .notFighting)
        var state = ActorConditionState(
            current: values.current(of: holder),
            maximums: values.maximums(of: holder),
            isDead: isDead,
            combatActivity: activity,
            weaponDrawState: drawState,
            general: values.resolvedEntries(of: holder),
            generalBaseline: baseline.basesByIndex,
            level: baseline.level,
            isChild: baseline.isChild,
            leftHandOut: handIsEmpty ? .nothing : nil,
            race: baseline.race
        )
        state.isFemale = baseline.isFemale
        state.isFlying = game.dragonFlightWorld.isFlying(holder.key)
        state.isInPairedAnimation = game.idleWorld.idles.pairedAnimation(of: holder.key) != nil
        state.raceKeywords = baseline.race == nil ? nil : baseline.raceKeywords
        state.injuredHealthPercent = baseline.injuredHealthPercent
        let record = holder.key == .player ? nil : baseline.recordFlags
        state.recordFlags = game.scripts.bridge?.actorFlags(of: holder.key, record: record)
            ?? record
        state.action = actionFacts(of: holder.key, isDead: isDead)
        state.isCommanded = game.magic.commanded.contains { $0.actor == holder.key }
        // OpenSky weighs only the player's load; an NPC carries any weight.
        state.isOverEncumbered = holder.key == .player ? inventoryFacts
            .playerIsOverEncumbered() : false
        state.holdsWeapon = game.inventory.conditionEquipment(of: holder.key).map { facts in
            facts.rightWeapon != nil || facts.leftWeapon != nil
        }
        return state
    }

    /// The player's from its melee and bow state; an NPC's from its combat behaviour, and
    /// standing still when it has none.
    private func actionFacts(of key: ReferenceKey, isDead: Bool) -> ActorActionFacts? {
        if key == .player {
            return game.combat.playerActionFacts
        }
        guard let loop = game.combat.loop else { return nil }
        guard !isDead, let facts = loop.actionFacts(of: key) else { return .still }
        return facts
    }

    public func store() async throws -> OpenSkySaveStore {
        if let saveStore {
            return saveStore
        }
        let store = try await OpenSkySaveStore.openDefault()
        saveStore = store
        return store
    }

    /// A failed build is not kept, so the next save tries again.
    public func pluginFingerprint() async throws -> [SavePluginFingerprint] {
        let task = fingerprint ?? Task { try await OpenSkySaveStore.installedFingerprint() }
        fingerprint = task
        do {
            return try await task.value
        } catch {
            fingerprint = nil
            throw error
        }
    }
}

extension RuntimeStateWorldAdapter: RuntimeStateWorld {}

/// Where resident references are, for one set of resident cells and reference count.
private struct ResidentReferencePlaces {
    let cells: Set<CellSceneLocation>
    let count: Int
    let places: ReferencePlaces
}

/// The record data every live condition reads. Each evaluator translates a record's
/// FormIDs into the load-order space, so the stores are read in that space.
extension RuntimeStateWorldAdapter {
    public func conditionData() -> ConditionDataResolution {
        let locationStore = game.worldData?.locationStore
        let places = currentReferencePlaces()
        return ConditionDataResolution(
            keywords: locationStore?.keywords,
            formLists: game.worldData?.formListStore,
            locations: locationStore,
            sourcePlugin: FormIDResolver.loadOrderSpaceName,
            currentLocations: places.locations,
            interiors: places.interiors,
            cells: places.cells
        )
    }

    /// The location a resident cell belongs to; nil without location data.
    public func location(of scene: any CellScenePort) -> ResolvedFormID? {
        location(of: scene.locationKey)
    }

    public func location(of key: CellLocationKey) -> ResolvedFormID? {
        cellLocationResolver()?.location(of: key)
    }

    /// The `NAM1` music type of a resident cell's location.
    public func locationMusicType(of scene: CellLocationKey) -> FormID? {
        cellLocationResolver()?.musicType(of: scene)
    }

    private func cellLocationResolver() -> CellLocationResolver? {
        if let cellLocations {
            return cellLocations
        }
        let store = game.worldData?.locationStore
        cellLocations = store.map { CellLocationResolver(store: $0) }
        return cellLocations
    }

    /// Where the player and each resident reference are now.
    private func currentReferencePlaces() -> ReferencePlaces {
        guard let streamer = game.streamer else { return ReferencePlaces() }
        let cells = streamer.residentCellLocations
        let count = streamer.residentReferenceCount
        var places: ReferencePlaces
        if let cached = referencePlaces, cached.cells == cells, cached.count == count {
            places = cached.places
        } else {
            places = streamer.residentReferencePlaces { [self] in location(of: $0) }
            referencePlaces = ResidentReferencePlaces(cells: cells, count: count, places: places)
        }
        if
            let current = streamer.currentCellLocation,
            let scene = streamer.residentScene(at: current)
        {
            places.locations[.player] = location(of: scene)
            places.interiors[.player] = scene.isInterior
            places.cells[.player] = scene.referenceCell
        }
        return places
    }
}

extension RuntimeStateWorldAdapter: RuntimeStateWorldPort {}
