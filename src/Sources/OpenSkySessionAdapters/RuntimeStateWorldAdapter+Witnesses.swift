import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
public import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySave
public import OpenSkySaveInterface
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
public import OpenSkyWorldState

/// Witnesses that forward to the narrow parts of `RuntimeStateWorldAdapter`.
extension RuntimeStateWorldAdapter {
    public func referenceEntry(formID: FormID) -> RuntimeReferenceEntry? {
        sessionClock.referenceEntry(formID: formID)
    }

    public var crosshairReference: FormID? {
        sessionClock.crosshairReference
    }

    public var gameClock: GameClock? {
        get { sessionClock.gameClock }
        set { sessionClock.gameClock = newValue }
    }

    public var timescale: Float? {
        sessionClock.timescale
    }

    public func setTimeOfDay(_ hour: Float) {
        sessionClock.setTimeOfDay(hour)
    }

    public func persistTimeOfDay(_ hour: Float) {
        sessionClock.persistTimeOfDay(hour)
    }

    public func projectTimeGlobal(_ global: GameClock.TimeGlobal, value: Float) -> Float? {
        sessionClock.projectTimeGlobal(global, value: value)
    }

    public func applyGlobalResolution(_ resolution: GlobalResolution, reroll: Bool) {
        sessionClock.applyGlobalResolution(resolution, reroll: reroll)
    }

    public var musicStore: MusicRecordStore? {
        sessionClock.musicStore
    }

    public var globalStore: GlobalStore? {
        sessionClock.globalStore
    }

    public func conditionContext(
        crosshair: RuntimeReferenceEntry?, globals: GlobalResolution, indexing: [ReferenceKey]
    ) -> ConditionContext {
        conditionReads.conditionContext(crosshair: crosshair, globals: globals, indexing: indexing)
    }

    public func saveSlots() async throws -> [String] {
        try await saveContents.saveSlots()
    }

    public func saveSession(slot: String) async throws {
        try await saveContents.saveSession(slot: slot)
    }

    public func saveSession(
        slot: String,
        summary: SaveSummary?,
        thumbnail: SaveThumbnail?
    ) async throws {
        try await saveContents.saveSession(slot: slot, summary: summary, thumbnail: thumbnail)
    }

    public func sessionContents(
        summary: SaveSummary?,
        thumbnail: SaveThumbnail?
    ) -> OpenSkySaveContents {
        saveContents.sessionContents(summary: summary, thumbnail: thumbnail)
    }

    public func writeImported(_ contents: OpenSkySaveContents, slot: String) async throws {
        try await saveContents.writeImported(contents, slot: slot)
    }

    public func saveListings() async throws -> [OpenSkySaveSlotListing] {
        try await saveContents.saveListings()
    }

    public func deleteSave(slot: String) async throws {
        try await saveContents.deleteSave(slot: slot)
    }

    public func loadSession(slot: String) async throws {
        try await sessionLoad.loadSession(slot: slot)
    }

    public func loadSession(slot: String, checksLoadOrder: Bool) async throws {
        try await sessionLoad.loadSession(slot: slot, checksLoadOrder: checksLoadOrder)
    }

    public func addLiveSeams(to context: inout ConditionContext) {
        liveSeams.addLiveSeams(to: &context)
    }
}
