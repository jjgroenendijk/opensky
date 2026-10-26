// App side of `RuntimeStateCoordinator`: answers `RuntimeStateWorld` from the
// renderer, the streamer, and the session systems, and runs save and load.
// The rules live in the coordinator (docs/engine/coordinators.md).

import Foundation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
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
import OpenSkyRuntimeState
import OpenSkySave
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `RuntimeStateWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol RuntimeStateWorldHost: AnyObject {
    var dragonFlightWorld: DragonFlightWorldAdapter { get }
    var actorGraphWorld: ActorGraphWorldAdapter { get }
    var actorValues: ActorValueCoordinator { get }
    var actorWorld: ActorWorldAdapter { get }
    var aiWorld: AIWorldAdapter { get }
    var combat: CombatCoordinator { get }
    var combatWorld: CombatWorldAdapter { get }
    var crime: CrimeCoordinator { get }
    var dialogue: DialogueCoordinator { get }
    var factions: FactionCoordinator { get }
    var hud: HUDCoordinator { get }
    var idleWorld: IdleWorldAdapter { get }
    var inventory: InventoryCoordinator { get }
    var magic: MagicCoordinator { get }
    var menuMode: MenuModeController { get }
    var menuWorld: MenuWorldAdapter { get }
    var messages: MessageCoordinator { get }
    var mountWorld: MountWorldAdapter { get }
    var packages: PackageCoordinator { get }
    var perception: PerceptionCoordinator { get }
    var gameSession: GameSession? { get }
    var scenes: SceneCoordinator { get }
    var scripts: ScriptCoordinator { get }
    var streamer: CellStreamer? { get }
    var vehicleWorld: VehicleWorldAdapter { get }
    var worldData: WorldDataStores? { get }
    var worldState: WorldStateStore { get }
}

final class RuntimeStateWorldAdapter {
    unowned let game: any RuntimeStateWorldHost
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
    let conditionCaches = ConditionViewCaches()

    init(game: any RuntimeStateWorldHost) {
        self.game = game
    }

    static var saveAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
    }

    /// Every resident actor plus the player, with the combat loop's fight
    /// filled in both directions.
    func actorResolution() -> ActorStateResolution {
        guard let values = game.actorValues.runtime else { return .empty }
        var player = actorConditionState(holder: .player, values: values)
        playerConditionTraits(&player)
        var states = residentActorStates(values: values)
        states[.player] = player
        return ActorStateResolution.fight(
            states: states, playerKey: .player, playerTarget: game.combat.loop?.state.target
        )
    }

    /// Actor values, death and equipment are store writes; the fight is each machine's phase.
    private func residentActorStates(values: ActorValueRuntime)
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
        values: ActorValueRuntime,
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
        state.raceKeywords = baseline.race == nil ? nil : baseline.raceKeywords
        if holder.key != .player {
            state.recordFlags = baseline.recordFlags
        }
        state.action = actionFacts(of: holder.key, isDead: isDead)
        // OpenSky weighs only the player's load; an NPC carries any weight.
        state.isOverEncumbered = holder.key == .player ? playerIsOverEncumbered() : false
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
        guard !isDead, let phase = loop.phase(of: key) else { return .still }
        return phase.actionFacts
    }

    private func store() async throws -> OpenSkySaveStore {
        if let saveStore {
            return saveStore
        }
        let store = try await OpenSkySaveStore.openDefault()
        saveStore = store
        return store
    }

    /// A failed build is not kept, so the next save tries again.
    private func pluginFingerprint() async throws -> [SavePluginFingerprint] {
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

extension RuntimeStateWorldAdapter: RuntimeStateWorld {
    func referenceEntry(formID: FormID) -> RuntimeReferenceEntry? {
        game.streamer?.referenceEntry(formID: formID)
    }

    var crosshairReference: FormID? {
        game.hud.interactionTarget?.interaction.reference
    }

    var gameClock: GameClock? {
        get { game.gameSession?.gameClock }
        set {
            // Setting the clock also resets the weather's elapsed-hours mark, so
            // a date jump ages no weather.
            if let newValue {
                game.gameSession?.gameClock = newValue
            }
        }
    }

    var timescale: Float? {
        game.gameSession?.currentTimescale
    }

    func setTimeOfDay(_ hour: Float) {
        game.gameSession?.timeOfDay = hour
    }

    func persistTimeOfDay(_ hour: Float) {
        TimeOfDaySettings.store(hour)
    }

    func projectTimeGlobal(_ global: GameClock.TimeGlobal, value: Float) -> Float? {
        guard let gameSession = game.gameSession else { return nil }
        let previous = gameSession.gameClock.projectedValue(global)
        gameSession.gameTime.clock.setProjectedValue(value, for: global)
        return previous
    }

    func applyGlobalResolution(_ resolution: GlobalResolution, reroll: Bool) {
        guard let gameSession = game.gameSession else { return }
        gameSession.gameTime.globalResolution = resolution
        gameSession.weather?.setGlobalResolution(resolution, reroll: reroll)
    }

    var musicStore: MusicRecordStore? {
        game.worldData?.musicStore
    }

    var globalStore: GlobalStore? {
        game.worldData?.globalStore
    }

    /// `aliasQuest` stays nil, because a music condition belongs to no quest.
    /// The references hold the crosshair and every resident actor, so a
    /// combat-target run-on resolves.
    func conditionContext(
        crosshair: RuntimeReferenceEntry?, globals: GlobalResolution, indexing: [ReferenceKey]
    ) -> ConditionContext {
        let quests = game.scripts.bridge?.questRuntime
        let references = references(crosshair: crosshair, indexing: indexing)
        var context = ConditionContext(
            globals: globals,
            quests: quests?.resolution() ?? .empty,
            aliases: quests?.aliasResolution() ?? .empty,
            actors: actorResolution(),
            detection: game.perception.perceptionResolution(),
            magic: game.magic.magicConditionResolution(),
            crime: game.crime.conditionResolution(owning: references.sortedKeys()),
            factions: game.factions.conditionResolution(),
            clock: game.gameSession?.gameClock,
            references: references,
            subject: crosshair?.key,
            target: crosshair?.key
        )
        context.data = conditionData()
        addLiveSeams(to: &context)
        return context
    }

    private func references(
        crosshair: RuntimeReferenceEntry?, indexing: [ReferenceKey]
    ) -> RuntimeReferenceIndex {
        var entries = crosshair.map { [$0] } ?? []
        var seen = Set(entries.map(\.key))
        for key in game.actorWorld.combatActors().map(\.key) + indexing {
            guard
                !seen.contains(key),
                let entry = game.streamer?.referenceEntry(key: key)
            else { continue }
            seen.insert(key)
            entries.append(entry)
        }
        return RuntimeReferenceIndex(entries: entries)
    }

    func saveSlots() async throws -> [String] {
        try await store().readSlots()
    }

    func saveSession(slot: String) async throws {
        try await saveSession(slot: slot, summary: nil, thumbnail: nil)
    }

    func saveSession(slot: String, summary: SaveSummary?, thumbnail: SaveThumbnail?) async throws {
        let contents = sessionContents(summary: summary, thumbnail: thumbnail)
        let store = try await store()
        try await store.write(contents, fingerprint: pluginFingerprint(), toSlot: slot)
    }

    /// The session as a save holds it. Arrows in flight and falling corpses are
    /// dropped first: a save that kept them would freeze an arrow in the air.
    func sessionContents(summary: SaveSummary?, thumbnail: SaveThumbnail?) -> OpenSkySaveContents {
        game.streamer?.persistNPCMovementForSave()
        game.combatWorld.run(game.combat.prepareForPersistence())
        return OpenSkySaveContents(
            snapshot: game.worldState.snapshot(),
            metadata: SaveCreationMetadata(
                creationTimestamp: UInt64(max(0, Date().timeIntervalSince1970)),
                appVersion: Self.saveAppVersion
            ),
            clock: game.gameSession?.gameClock,
            scripts: game.scripts.runtime?.instanceStates() ?? [],
            timers: game.scripts.runtime?.timerStates() ?? [],
            summary: summary,
            thumbnail: thumbnail,
            playerPlace: playerPlace()
        )
    }

    /// An imported Skyrim save is written as an ordinary slot, so it loads through
    /// the one restore path.
    func writeImported(_ contents: OpenSkySaveContents, slot: String) async throws {
        let store = try await store()
        try await store.write(contents, fingerprint: pluginFingerprint(), toSlot: slot)
    }

    func saveListings() async throws -> [OpenSkySaveSlotListing] {
        try await store().readListings()
    }

    func deleteSave(slot: String) async throws {
        try await store().remove(slot: slot)
    }

    /// A missing install skips fingerprint verification instead of blocking the
    /// load; the file's own contents are still checked.
    func loadSession(slot: String) async throws {
        let current = try? await pluginFingerprint()
        let file = try await store().read(slot: slot, verifyingAgainst: current)
        game.worldState.restore(from: file.snapshot)
        // No plugin holds a brewed potion, so the save's own list goes in the item index.
        game.inventory.registerCreatedPotions()
        // A save without a CLOK chunk restores the vanilla-start clock.
        game.gameSession?.gameClock = file.clock ?? GameClock()
        // After the world state, so the fired `OnInit` set is in place before the
        // queued cell rebuilds re-attach scripts.
        game.scripts.restore(instances: file.scripts, timers: file.timers)
        game.scripts.bridge?.publishFactionReactions()
        game.combatWorld.run(game.combat.prepareForPersistence())
        game.messages.reloadHelpRecords()
        // `AVOV` keeps no temporary modifiers, so the restored effects rebuild
        // them: the player now, every other actor when its cell streams back in.
        game.magic.noteEffectsRestored()
        if let place = file.playerPlace {
            game.menuWorld.restorePlayerPlace(place)
        }
    }

    /// Interior coordinates are local to the cell, as the camera holds them there.
    /// The restore stands the player at these feet, so fly mode saves the camera.
    private func playerPlace() -> SavePlayerPlace? {
        guard
            let streamer = game.streamer, let cell = streamer.currentCellLocation,
            let gameSession = game.gameSession
        else { return nil }
        let feet = gameSession.movementMode.isPlayerControlled
            ? gameSession.walkController.feetPosition : gameSession.freeFlyCamera.position
        let worldspace: String? = switch cell {
        case .exterior: streamer.worldspaceEditorID
        case .interior: nil
        }
        return SavePlayerPlace(
            cell: cell, feet: feet, yaw: gameSession.freeFlyCamera.yaw, worldspace: worldspace
        )
    }
}

/// Where resident references are, for one set of resident cells and reference count.
private struct ResidentReferencePlaces {
    let cells: Set<CellSceneLocation>
    let count: Int
    let places: ReferencePlaces
}

/// Each reference's location and whether its cell is an interior.
private struct ReferencePlaces {
    var locations: [ReferenceKey: ResolvedFormID] = [:]
    var interiors: [ReferenceKey: Bool] = [:]
    var cells: [ReferenceKey: ReferenceCell] = [:]
}

/// The record data every live condition reads. Each evaluator translates a record's
/// FormIDs into the load-order space, so the stores are read in that space.
extension RuntimeStateWorldAdapter {
    func conditionData() -> ConditionDataResolution {
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
    func location(of scene: CellScene) -> ResolvedFormID? {
        cellLocationResolver()?.location(of: scene)
    }

    /// The `NAM1` music type of a resident cell's location.
    func locationMusicType(of scene: CellScene) -> FormID? {
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
            places = residentPlaces(in: streamer.residentScenes)
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

    private func residentPlaces(in scenes: [CellScene]) -> ReferencePlaces {
        var places = ReferencePlaces()
        places.locations = cellLocationResolver()?.referenceLocations(in: scenes) ?? [:]
        for scene in scenes {
            let cell = scene.referenceCell
            for entry in scene.references.sortedEntries() {
                places.interiors[entry.key] = scene.isInterior
                places.cells[entry.key] = cell
            }
        }
        return places
    }
}
