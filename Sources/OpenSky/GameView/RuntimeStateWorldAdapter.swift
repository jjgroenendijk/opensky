// App side of `RuntimeStateCoordinator`: answers `RuntimeStateWorld` from the
// renderer, the streamer, and the session systems, and runs save and load.
// The rules live in the coordinator (docs/engine/coordinators.md).

import Foundation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAudio
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkySave
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

final class RuntimeStateWorldAdapter {
    unowned let game: GameViewController
    /// Resolved once: retrying an unwritable Application Support on every
    /// readout tick would hit the disk for the same answer.
    private var saveStore: OpenSkySaveStore?
    /// Parses every plugin header, so it is built once per session.
    private var fingerprint: Task<[SavePluginFingerprint], any Error>?

    init(game: GameViewController) {
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
        var states: [ReferenceKey: ActorConditionState] = [
            .player: actorConditionState(holder: .player, values: values)
        ]
        for observation in game.actorWorld.combatActors() {
            guard let holder = game.actorWorld.actorValueHolder(for: observation.key) else {
                continue
            }
            states[observation.key] = actorConditionState(
                holder: holder, values: values, isDead: observation.isDead
            )
        }
        return ActorStateResolution.fight(
            states: states, playerKey: .player, playerTarget: game.combat.loop?.state.target
        )
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
        return ActorConditionState(
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
    var residentReferenceCount: Int {
        game.streamer?.residentReferenceCount ?? 0
    }

    func referenceEntry(formID: FormID) -> RuntimeReferenceEntry? {
        game.streamer?.referenceEntry(formID: formID)
    }

    var crosshairReference: FormID? {
        game.hud.interactionTarget?.interaction.reference
    }

    var gameClock: GameClock? {
        get { game.renderer?.gameClock }
        set {
            // Setting the clock also resets the weather's elapsed-hours mark, so
            // a date jump ages no weather.
            if let newValue {
                game.renderer?.gameClock = newValue
            }
        }
    }

    var timescale: Float? {
        game.renderer?.currentTimescale
    }

    var isWorldSimPaused: Bool {
        game.renderer?.worldSimPaused ?? false
    }

    func setTimeOfDay(_ hour: Float) {
        game.renderer?.timeOfDay = hour
    }

    func persistTimeOfDay(_ hour: Float) {
        TimeOfDaySettings.store(hour)
    }

    func projectTimeGlobal(_ global: GameClock.TimeGlobal, value: Float) -> Float? {
        guard let renderer = game.renderer else { return nil }
        let previous = renderer.gameClock.projectedValue(global)
        renderer.gameTime.clock.setProjectedValue(value, for: global)
        return previous
    }

    func applyGlobalResolution(_ resolution: GlobalResolution, reroll: Bool) {
        guard let renderer = game.renderer else { return }
        renderer.gameTime.globalResolution = resolution
        renderer.weather?.setGlobalResolution(resolution, reroll: reroll)
    }

    var musicStore: MusicRecordStore? {
        (game.worldData as? AudioDataProviding)?.musicStore
    }

    /// `aliasQuest` stays nil, because a music condition belongs to no quest.
    /// The references hold the crosshair and every resident actor, so a
    /// combat-target run-on resolves.
    func conditionContext(
        crosshair: RuntimeReferenceEntry?, globals: GlobalResolution
    ) -> ConditionContext {
        let quests = game.scripts.bridge?.questRuntime
        return ConditionContext(
            globals: globals,
            quests: quests?.resolution() ?? .empty,
            aliases: quests?.aliasResolution() ?? .empty,
            actors: actorResolution(),
            detection: game.perception.perceptionResolution(),
            magic: game.magic.magicConditionResolution(),
            crime: game.crime.conditionResolution(),
            factions: game.factions.conditionResolution(),
            clock: game.renderer?.gameClock,
            references: references(crosshair: crosshair),
            subject: crosshair?.key,
            target: crosshair?.key
        )
    }

    private func references(crosshair: RuntimeReferenceEntry?) -> RuntimeReferenceIndex {
        var entries = crosshair.map { [$0] } ?? []
        for observation in game.actorWorld.combatActors() {
            guard
                let entry = game.streamer?.referenceEntry(key: observation.key),
                entry.key != crosshair?.key
            else { continue }
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

    /// Arrows in flight and falling corpses are dropped first: neither survives
    /// a reload, and a save that kept them would freeze an arrow in the air.
    func saveSession(slot: String, summary: SaveSummary?, thumbnail: SaveThumbnail?) async throws {
        game.streamer?.persistNPCMovementForSave()
        game.combat.loop?.prepareForPersistence()
        let contents = OpenSkySaveContents(
            snapshot: game.worldState.snapshot(),
            metadata: SaveCreationMetadata(
                creationTimestamp: UInt64(max(0, Date().timeIntervalSince1970)),
                appVersion: Self.saveAppVersion
            ),
            clock: game.renderer?.gameClock,
            scripts: game.scripts.runtime?.instanceStates() ?? [],
            timers: game.scripts.runtime?.timerStates() ?? [],
            summary: summary,
            thumbnail: thumbnail,
            playerPlace: playerPlace()
        )
        let store = try await store()
        try await store.write(contents, fingerprint: pluginFingerprint(), toSlot: slot)
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
        // A save without a CLOK chunk restores the vanilla-start clock.
        game.renderer?.gameClock = file.clock ?? GameClock()
        // After the world state, so the fired `OnInit` set is in place before the
        // queued cell rebuilds re-attach scripts.
        game.scripts.restore(instances: file.scripts, timers: file.timers)
        game.combat.loop?.prepareForPersistence()
        game.messages.reloadHelpRecords()
        // `AVOV` keeps no temporary modifiers, so the restored effects rebuild
        // them. Player only: other actors have no holder until their cells
        // stream back in (docs/engine/magic.md).
        game.magic.withEffects { $0.reestablishModifiers(on: .player) }
        if let place = file.playerPlace {
            game.menuWorld.restorePlayerPlace(place)
        }
    }

    /// Interior coordinates are local to the cell, as the camera holds them there.
    /// The restore stands the player at these feet, so fly mode saves the camera.
    private func playerPlace() -> SavePlayerPlace? {
        guard let cell = game.streamer?.currentCellLocation, let renderer = game.renderer else {
            return nil
        }
        let feet = renderer.movementMode.isPlayerControlled
            ? renderer.walkController.feetPosition : renderer.freeFlyCamera.position
        return SavePlayerPlace(cell: cell, feet: feet, yaw: renderer.freeFlyCamera.yaw)
    }
}
