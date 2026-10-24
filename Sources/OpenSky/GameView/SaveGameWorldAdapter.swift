// Saving and loading for the system menu, the quick keys, and autosaves. Each
// save carries a summary and a small picture for the save list.

import Foundation
import Metal
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyProgression
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkySave
import OpenSkyWorld

/// What `SaveGameWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol SaveGameWorldHost: SkyrimSaveExportHost, SkyrimSaveImportHost {
    var mapWorld: MapWorldAdapter { get }
    var menuWorld: MenuWorldAdapter { get }
    var playerSettings: PlayerSettingsCoordinator { get }
    var progression: ProgressionCoordinator { get }
    var renderer: Renderer? { get }
    var runtimeStateWorld: RuntimeStateWorldAdapter { get }
    var streamer: CellStreamer? { get }
    var worldData: WorldDataStores? { get }
}

@MainActor
final class SaveGameWorldAdapter: SaveGameService {
    static let thumbnailSize = (width: 192, height: 108)

    private unowned let game: any SaveGameWorldHost
    private let autosaves = AutosavePolicy()
    /// When the last save of any kind was written, for Save on Pause.
    private(set) var lastSaveDate: Date?
    private var sessionStart = Date()
    private var playSecondsBefore: Double = 0
    /// The newest listing, so menus and autosave dates need no disk read.
    private var listings: [OpenSkySaveSlotListing] = []
    private(set) var saveRows: [SaveSlotRow] = []
    private(set) var lastSkyrimExport = SkyrimExportOutcome.none
    private var hasListed = false

    init(game: any SaveGameWorldHost) {
        self.game = game
    }

    /// The OpenSky saves, without the Skyrim imports.
    private var ownRows: [SaveSlotRow] {
        saveRows.filter { !$0.isImport }
    }

    /// A listing failure reads as no saves: the list is a readout.
    @discardableResult
    func refreshSaveRows() async -> [SaveSlotRow] {
        listings = await (try? game.runtimeStateWorld.saveListings()) ?? []
        let texts = saveTexts
        saveRows = await listings.map { Self.row($0, texts: texts) }
            + SkyrimSaveImportAdapter.rows()
        hasListed = true
        return saveRows
    }

    /// The summary and picture are taken now, before the file work starts.
    @discardableResult
    func saveGame(slot: String?) async throws -> String {
        let name = slot ?? Self.newSlotName(existing: Set(ownRows.map(\.slot)))
        lastSaveDate = Date()
        try await game.runtimeStateWorld.saveSession(
            slot: name, summary: summary(), thumbnail: thumbnail()
        )
        await refreshSaveRows()
        return name
    }

    /// The summary and picture are taken now, as for an OpenSky save.
    @discardableResult
    func exportSkyrimSave() async throws -> String {
        let contents = game.runtimeStateWorld.sessionContents(
            summary: summary(), thumbnail: thumbnail()
        )
        lastSkyrimExport = .running
        do {
            let (url, report) = try await SkyrimSaveExportAdapter.export(contents, game: game)
            lastSkyrimExport = .exported(url.lastPathComponent, report.lines)
            await refreshSaveRows()
            return url.lastPathComponent
        } catch {
            lastSkyrimExport = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Play time continues from the loaded save. A Skyrim save starts it from zero.
    func loadGame(slot: String) async throws {
        if SkyrimSaveImportAdapter.isImport(slot) {
            try await SkyrimSaveImportAdapter.load(slot: slot, game: game)
            await refreshSaveRows()
            resetPlayTime()
            lastSaveDate = Date()
            return
        }
        if !listings.contains(where: { $0.slot == slot }) {
            await refreshSaveRows()
        }
        let playSeconds = listings.first { $0.slot == slot }?.summary?.summary?.playSeconds
        try await game.runtimeStateWorld.loadSession(slot: slot)
        playSecondsBefore = playSeconds ?? 0
        sessionStart = Date()
        lastSaveDate = Date()
    }

    func deleteSave(slot: String) async throws {
        guard !SkyrimSaveImportAdapter.isImport(slot) else { return }
        try await game.runtimeStateWorld.deleteSave(slot: slot)
        await refreshSaveRows()
    }

    /// A new game counts play time from zero.
    func resetPlayTime() {
        playSecondsBefore = 0
        sessionStart = Date()
        lastSaveDate = nil
    }

    func quickload() {
        let notices = game.mapWorld.settingTexts(SaveNoticeText.self)
        Task {
            if !hasListed {
                await refreshSaveRows()
            }
            guard listings.contains(where: { $0.slot == AutosavePolicy.quicksaveSlot }) else {
                game.hud.showNotification(notices[.noSave])
                return
            }
            game.hud.showNotification(notices[.quickloading])
            do {
                try await loadGame(slot: AutosavePolicy.quicksaveSlot)
            } catch {
                Self.logger
                    .error("[ERROR] quickload: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Papyrus `RequestSave` and `RequestAutoSave`: a save the script asked for, written
    /// whatever the autosave settings say. False when no session is running.
    func requestSave(autosave: Bool) -> Bool {
        guard game.streamer != nil else { return false }
        Task {
            if !hasListed {
                await refreshSaveRows()
            }
            let dates = Dictionary(ownRows.map { ($0.slot, $0.savedAt) }) { first, _ in first }
            do {
                try await saveGame(slot: autosave ? autosaves.nextSlot(saved: dates) : nil)
            } catch {
                Self.logger
                    .error("[ERROR] script save: \(String(describing: error), privacy: .public)")
            }
        }
        return true
    }

    /// Writes an autosave when the player's settings ask for one.
    func autosave(_ trigger: AutosaveTrigger) {
        let settings = game.playerSettings.store
        let due = trigger == .pause
            ? autosaves.shouldSaveOnPause(settings: settings, lastSave: lastSaveDate, now: Date())
            : autosaves.isEnabled(trigger, settings: settings)
        guard due else { return }
        game.hud.showNotification(game.mapWorld.settingTexts(SaveNoticeText.self)[.autosaving])
        Task {
            if !hasListed {
                await refreshSaveRows()
            }
            let dates = Dictionary(ownRows.map { ($0.slot, $0.savedAt) }) { first, _ in first }
            do {
                try await saveGame(slot: autosaves.nextSlot(saved: dates))
            } catch {
                Self.logger
                    .error("[ERROR] autosave: \(String(describing: error), privacy: .public)")
            }
        }
    }

    static func newSlotName(existing: Set<String>) -> String {
        var number = existing.count + 1
        while existing.contains("Save \(number)") {
            number += 1
        }
        return "Save \(number)"
    }

    var saveTexts: SaveTexts {
        game.worldData.map {
            SaveTexts.resolve(store: $0.gameSettings) { [game] in game.mapWorld.text($0) }
        } ?? .vanilla
    }

    static func row(
        _ listing: OpenSkySaveSlotListing, texts: SaveTexts = .vanilla
    ) -> SaveSlotRow {
        let summary = listing.summary?.summary
        let savedAt = listing.summary.map {
            Date(timeIntervalSince1970: TimeInterval($0.metadata.creationTimestamp))
        } ?? listing.modified
        let title = summary.map { "\(listing.slot) - \($0.characterName)" } ?? listing.slot
        let detail = summary.map {
            "\(texts.level) \($0.level), \($0.locationName), \(playTimeText($0.playSeconds))"
        } ?? listing.error ?? ""
        let thumbnail = listing.summary?.thumbnail
        return SaveSlotRow(
            slot: listing.slot, title: title, detail: detail, savedAt: savedAt,
            hasThumbnail: thumbnail != nil, error: listing.error,
            character: summary.map {
                SaveSlotCharacter(
                    name: $0.characterName, race: $0.raceName, level: $0.level,
                    playTime: playTimeText($0.playSeconds)
                )
            },
            picture: thumbnail.map {
                SaveSlotPicture(width: $0.width, height: $0.height, rgba: $0.rgba)
            }
        )
    }

    static func playTimeText(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    private func summary() -> SaveSummary {
        let identity = game.menuWorld.playerNameAndRace
        return SaveSummary(
            characterName: identity.name, level: game.progression.leveling?.level ?? 1,
            raceName: identity.race, locationName: locationName(),
            playSeconds: playSecondsBefore + Date().timeIntervalSince(sessionStart)
        )
    }

    private func locationName() -> String {
        let texts = saveTexts
        return switch game.streamer?.currentCellLocation {
        case let .exterior(cell): "\(texts.wilderness) \(cell.x), \(cell.y)"
        case let .interior(formID): "Interior \(formID)"
        case nil: texts.unknownLocation
        }
    }

    private func thumbnail() -> SaveThumbnail? {
        guard
            let texture = try? game.renderer?.renderOffscreen(
                width: Self.thumbnailSize.width, height: Self.thumbnailSize.height
            )
        else { return nil }
        return SaveThumbnail(
            width: texture.width, height: texture.height,
            rgba: FrameScreenshot.rgbaBytes(from: texture)
        )
    }

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Saves"
    )
}
