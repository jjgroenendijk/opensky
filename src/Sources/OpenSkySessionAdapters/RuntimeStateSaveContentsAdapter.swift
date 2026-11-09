import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySave
public import OpenSkySaveInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `RuntimeStateSaveContentsAdapter` reads from the session.
@MainActor
public protocol RuntimeStateSaveContentsHost: AnyObject {
    var combat: any CombatPort { get }
    var combatWorld: any CombatWorldPort { get }
    var crime: any CrimePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var magic: any MagicPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `RuntimeStateWorldAdapter`, over its own narrow host.
public struct RuntimeStateSaveContentsAdapter {
    public let game: any RuntimeStateSaveContentsHost
    public let core: RuntimeStateCoreAdapter
    public let sessionClock: RuntimeStateSessionClockAdapter
}

extension RuntimeStateSaveContentsAdapter {
    public func saveSlots() async throws -> [String] {
        try await core.store().readSlots()
    }

    public func saveSession(slot: String) async throws {
        try await saveSession(slot: slot, summary: nil, thumbnail: nil)
    }

    public func saveSession(
        slot: String,
        summary: SaveSummary?,
        thumbnail: SaveThumbnail?
    ) async throws {
        let contents = sessionContents(summary: summary, thumbnail: thumbnail)
        let store = try await core.store()
        try await store.write(contents, fingerprint: core.pluginFingerprint(), toSlot: slot)
    }

    /// The session as a save holds it. Arrows in flight and falling corpses are
    /// dropped first: a save that kept them would freeze an arrow in the air.
    public func sessionContents(
        summary: SaveSummary?,
        thumbnail: SaveThumbnail?
    ) -> OpenSkySaveContents {
        game.streamer.persistNPCMovementForSave()
        game.combatWorld.run(game.combat.prepareForPersistence())
        storeRuntimeExtras()
        return OpenSkySaveContents(
            snapshot: game.worldState.snapshot(),
            metadata: SaveCreationMetadata(
                creationTimestamp: UInt64(max(0, Date().timeIntervalSince1970)),
                appVersion: SaveAppVersion.current
            ),
            clock: game.gameSession?.gameClock,
            scripts: game.scripts.runtime?.instanceStates() ?? [],
            timers: game.scripts.runtime?.timerStates() ?? [],
            summary: summary,
            thumbnail: thumbnail,
            playerPlace: sessionClock.playerPlace()
        )
    }

    /// An imported Skyrim save is written as an ordinary slot, so it loads through
    /// the one restore path.
    public func writeImported(_ contents: OpenSkySaveContents, slot: String) async throws {
        let store = try await core.store()
        try await store.write(contents, fingerprint: core.pluginFingerprint(), toSlot: slot)
    }

    public func saveListings() async throws -> [OpenSkySaveSlotListing] {
        try await core.store().readListings()
    }

    public func deleteSave(slot: String) async throws {
        try await core.store().remove(slot: slot)
    }

    private enum Extra {
        static let shoutCooldown = "engine:shoutCooldown"
        static let jailNonViolent = "engine:jailNonViolentGold"
        static let jailViolent = "engine:jailViolentGold"
        static let jailDays = "engine:jailDays"
        static let jailFaction = "engine:jailFaction"
        static let jailMarker = "engine:jailMarker"
        static let jailBelongings = "engine:jailBelongings"
        static func jailOutfit(_ index: Int) -> String {
            "engine:jailOutfit\(index)"
        }
    }

    /// Writes the state just before the snapshot is taken.
    public func storeRuntimeExtras() {
        guard let bridge = game.scripts.bridge else { return }
        let cooldown = game.magic.shoutMachine.cooldown
        let stay = game.crime.jailStay
        let outfit = stay?.outfit.compactMap(bridge.referenceKey(forFormID:)) ?? []
        bridge.updateScriptedState(of: .player) { state in
            state.setValue(Extra.shoutCooldown, cooldown > 0 ? cooldown : nil)
            state.setValue(Extra.jailNonViolent, stay.map { Float($0.nonViolentGold) })
            state.setValue(Extra.jailViolent, stay.map { Float($0.violentGold) })
            state.setValue(Extra.jailDays, stay.map { Float($0.sentenceDays) })
            state.setForm(Extra.jailFaction, stay?.faction)
            state.setForm(Extra.jailMarker, stay?.exteriorMarker)
            state.setForm(Extra.jailBelongings, stay?.belongings)
            for index in 0 ..< max(outfit.count, Self.maximumOutfitPieces) {
                state.setForm(Extra.jailOutfit(index), index < outfit.count ? outfit[index] : nil)
            }
        }
    }

    /// Reads the state back after the world state of a save is restored.
    public func restoreRuntimeExtras() {
        guard let bridge = game.scripts.bridge else { return }
        let state = bridge.scriptedState(of: .player)
        game.magic.restoreShoutCooldown(state.value(Extra.shoutCooldown) ?? 0)
        guard
            let faction = state.form(Extra.jailFaction),
            let marker = state.form(Extra.jailMarker)
        else {
            game.crime.restoreJailStay(nil)
            return
        }
        let outfit = (0 ..< Self.maximumOutfitPieces).compactMap {
            state.form(Extra.jailOutfit($0)).flatMap(bridge.localFormID(of:))
        }
        game.crime.restoreJailStay(JailStay(
            faction: faction,
            nonViolentGold: Int32(state.value(Extra.jailNonViolent) ?? 0),
            violentGold: Int32(state.value(Extra.jailViolent) ?? 0),
            sentenceDays: Int(state.value(Extra.jailDays) ?? 0),
            exteriorMarker: marker,
            belongings: state.form(Extra.jailBelongings),
            outfit: outfit,
            arrestedIn: nil
        ))
    }

    /// A jail outfit has a few pieces; the slots past it are cleared on each save.
    private static let maximumOutfitPieces = 8
}
