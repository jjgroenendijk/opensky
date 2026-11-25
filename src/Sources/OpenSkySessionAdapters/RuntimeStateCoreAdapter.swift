import Foundation
import OpenSkyActorPresentation
public import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkySave
import OpenSkySaveInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// The runtime state reads that use the shared caches: actor and condition views,
/// cell locations, and the save store.
public struct RuntimeStateCoreAdapter {
    public let game: any RuntimeStateWorldHost
    public let state: RuntimeStatePartState
    public let inventoryFacts: RuntimeStateInventoryFactsAdapter
}

/// One actor's condition state: its values, fight, equipment, and flags.
struct ActorConditionReads {
    let game: any RuntimeStateWorldHost
    let inventoryFacts: RuntimeStateInventoryFactsAdapter

    /// The player's graph tracks its draw state; an NPC's follows its fight, through
    /// the combat loop. OpenSky draws no torch, and a shield comes out only with a drawn weapon,
    /// so a sheathed or peaceful actor holds nothing out.
    func actorConditionState(
        holder: ActorValueHolder,
        values: any ActorValueRuntimePort,
        isDead: Bool = false
    ) -> ActorConditionState {
        let baseline = values.baseline(of: holder)
        let activity = game.combat.loop?.activity(of: holder.key) ?? .notFighting
        let drawState = holder.key == .player
            ? game.combat.melee?.state.drawState
            : game.combat.loop?.drawState(of: holder.key) ?? WeaponDrawState.ofNPC(activity)
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
        state.holdsWeapon = game.inventory.itemConditions.conditionEquipment(of: holder.key)
            .map { facts in
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
}

extension RuntimeStateCoreAdapter {
    /// Every resident actor plus the player, with the combat loop's fight
    /// filled in both directions.
    public func actorResolution() -> ActorStateResolution {
        guard let values = game.actorValues.runtime else { return .empty }
        var player = ActorConditionReads(game: game, inventoryFacts: inventoryFacts)
            .actorConditionState(holder: .player, values: values)
        inventoryFacts.playerTraits.fill(&player)
        var states = ResidentActorStates(
            game: game, state: state, inventoryFacts: inventoryFacts
        ).residentActorStates(values: values)
        // An NPC swims while its mover does; one that stands has no mover and is on land.
        let swimmers = game.streamer.npcMovement.swimmingActors()
        for key in states.keys {
            states[key]?.isSwimming = swimmers.contains(key)
        }
        states[.player] = player
        return ActorStateResolution.fight(
            states: states, playerKey: .player, playerTarget: game.combat.loop?.state.target
        )
    }

    public func store() async throws -> OpenSkySaveStore {
        if let saveStore = state.saveStore {
            return saveStore
        }
        let store = try await OpenSkySaveStore.openDefault()
        state.saveStore = store
        return store
    }

    /// A failed build is not kept, so the next save tries again.
    public func pluginFingerprint() async throws -> [SavePluginFingerprint] {
        let task = state.fingerprint ?? Task { try await OpenSkySaveStore.installedFingerprint() }
        state.fingerprint = task
        do {
            return try await task.value
        } catch {
            state.fingerprint = nil
            throw error
        }
    }
}

/// The record data every live condition reads. Each evaluator translates a record's
/// FormIDs into the load-order space, so the stores are read in that space.
extension RuntimeStateCoreAdapter {
    public func conditionData() -> ConditionDataResolution {
        let locationStore = game.sessionRecords?.locationStore
        let resident = currentReferencePlaces()
        let places = resident.places
        return ConditionDataResolution(
            keywords: locationStore?.keywords,
            formLists: game.sessionRecords?.formListStore,
            locations: locationStore,
            sourcePlugin: FormIDResolver.loadOrderSpaceName,
            currentLocations: places.locations,
            editorLocations: resident.editorLocations,
            interiors: places.interiors,
            cells: places.cells
        )
    }

    /// A listed unique actor keeps the location its record names. Any other resident
    /// reference takes the location of the cell that holds its record, where it was placed
    /// (docs/formats/locations.md#editor-location).
    static func editorLocations(
        places: ReferencePlaces, store: LocationStore?
    ) -> [ReferenceKey: ResolvedFormID] {
        var locations = places.locations
        locations[.player] = nil
        return locations.merging(store?.editorLocations ?? [:]) { _, listed in listed }
    }

    /// The location a resident cell belongs to; nil without location data.
    func location(of scene: any CellScenePort) -> ResolvedFormID? {
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
        if let cellLocations = state.cellLocations {
            return cellLocations
        }
        let store = game.sessionRecords?.locationStore
        state.cellLocations = store.map { CellLocationResolver(store: $0) }
        return state.cellLocations
    }

    /// Where the player and each resident reference are now.
    /// Kept while the resident cells, their reference count, and the player's cell stay
    /// the same, with the player's place in it, so a build copies none of the maps.
    private func currentReferencePlaces() -> ResidentReferencePlaces {
        let streamer = game.streamer
        let cells = streamer.residentCellLocations
        let count = streamer.residentReferenceCount
        let current = streamer.currentCellLocation
        if
            let cached = state.referencePlaces, cached.cells == cells, cached.count == count,
            cached.current == current
        {
            return cached
        }
        var places = streamer.residentReferencePlaces { [self] in location(of: $0) }
        if let current, let scene = streamer.residentScene(at: current) {
            places.locations[.player] = location(of: scene)
            places.interiors[.player] = scene.isInterior
            places.cells[.player] = scene.referenceCell
        }
        let resident = ResidentReferencePlaces(
            cells: cells, count: count, current: current, places: places,
            editorLocations: Self.editorLocations(
                places: places, store: game.sessionRecords?.locationStore
            )
        )
        state.referencePlaces = resident
        return resident
    }
}

extension RuntimeStateWorldAdapter: RuntimeStateWorldPort {}

/// The condition state of every resident actor, cached until a store write or a fight changes.
@MainActor
struct ResidentActorStates {
    let game: any RuntimeStateWorldHost
    let state: RuntimeStatePartState
    let inventoryFacts: RuntimeStateInventoryFactsAdapter

    /// Actor values, death and equipment are store writes; the fight is each machine's phase.
    func residentActorStates(values: any ActorValueRuntimePort)
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
            phases: game.combat.loop?.behaviors.mapValues(\.phase),
            draws: game.combat.loop.map { loop in
                members.reduce(into: [:]) { draws, member in
                    draws[member.holder.key] = loop.drawState(of: member.holder.key)
                }
            }
        )
        return state.conditionCaches.actors.value(for: key) {
            members.reduce(into: [:]) { states, member in
                states[member.holder.key] = ActorConditionReads(
                    game: game, inventoryFacts: inventoryFacts
                ).actorConditionState(
                    holder: member.holder, values: values, isDead: member.isDead
                )
            }
        }
    }
}
