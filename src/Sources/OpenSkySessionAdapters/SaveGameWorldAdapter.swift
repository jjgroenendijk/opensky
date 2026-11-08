// Saving and loading for the system menu, the quick keys, and autosaves. Each
// save carries a summary and a small picture for the save list.

public import Foundation
import Metal
public import OpenSkyCells
import OpenSkyFormatsCore
public import OpenSkyGameData
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyProgression
public import OpenSkyRendering
import OpenSkyRenderResources
public import OpenSkySave
public import OpenSkySaveInterface
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld

/// What `SaveGameWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol SaveGameWorldHost: AnyObject {
    var hud: any HUDPort { get }
    var scripts: any ScriptPort { get }
    var effectsWorld: any EffectsWorldPort { get }
    var mapWorld: any MapWorldPort { get }
    var menuWorld: any MenuWorldPort { get }
    var playerSettings: any PlayerSettingsPort { get }
    var progression: any ProgressionPort { get }
    var renderer: (any RendererPort)? { get }
    var runtimeStateWorld: any RuntimeStateWorldPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
}

@MainActor
public final class SaveGameWorldAdapter: SaveGameService {
    public static let thumbnailSize = (width: 192, height: 108)

    private unowned let game: any SaveGameWorldHost
    private unowned let saveFiles: any SkyrimSaveExportHost & SkyrimSaveImportHost
    private let autosaves = AutosavePolicy()
    /// When the last save of any kind was written, for Save on Pause.
    public private(set) var lastSaveDate: Date?
    private var sessionStart = Date()
    private var playSecondsBefore: Double = 0
    /// The newest listing, so menus and autosave dates need no disk read.
    private var listings: [OpenSkySaveSlotListing] = []
    public private(set) var saveRows: [SaveSlotRow] = []
    public private(set) var lastSkyrimExport = SkyrimExportOutcome.none
    private var hasListed = false
    /// An autosave found the disk full; autosaves stay off until the app restarts.
    private var autosavesDisabled = false

    public init(game: some SaveGameWorldHost & SkyrimSaveExportHost & SkyrimSaveImportHost) {
        self.game = game
        saveFiles = game
    }

    /// The OpenSky saves, without the Skyrim imports.
    private var ownRows: [SaveSlotRow] {
        saveRows.filter { !$0.isImport }
    }

    /// A listing failure reads as no saves: the list is a readout.
    @discardableResult
    public func refreshSaveRows() async -> [SaveSlotRow] {
        listings = await attempt { try await game.runtimeStateWorld.saveListings() } ?? []
        let texts = saveTexts
        saveRows = await listings.map { Self.row($0, texts: texts) }
            + SkyrimSaveImport.rows()
        hasListed = true
        return saveRows
    }

    /// The summary and picture are taken now, before the file work starts.
    @discardableResult
    public func saveGame(slot: String?) async throws -> String {
        let name = slot ?? Self.newSlotName(existing: Set(ownRows.map(\.slot)))
        lastSaveDate = Date()
        do {
            try await game.runtimeStateWorld.saveSession(
                slot: name, summary: summary(), thumbnail: thumbnail()
            )
        } catch {
            throw Self.failure(error)
        }
        await refreshSaveRows()
        return name
    }

    public var isSavingDisabled: Bool {
        game.scripts.bridge?.playerControlLocks.savingDisabled ?? false
    }

    /// The summary and picture are taken now, as for an OpenSky save.
    @discardableResult
    public func exportSkyrimSave() async throws -> String {
        let contents = game.runtimeStateWorld.sessionContents(
            summary: summary(), thumbnail: thumbnail()
        )
        lastSkyrimExport = .running
        do {
            let (url, report) = try await SkyrimSaveExport.export(contents, game: saveFiles)
            lastSkyrimExport = .exported(url.lastPathComponent, report.lines)
            await refreshSaveRows()
            return url.lastPathComponent
        } catch {
            lastSkyrimExport = .failed(error.localizedDescription)
            throw error
        }
    }

    public func loadGame(slot: String) async throws {
        try await loadGame(slot: slot, acceptingChangedContent: false)
    }

    /// Play time continues from the loaded save. A Skyrim save starts it from zero.
    public func loadGame(slot: String, acceptingChangedContent: Bool) async throws {
        do {
            try await load(slot: slot, checksLoadOrder: !acceptingChangedContent)
        } catch {
            throw Self.failure(error)
        }
    }

    private func load(slot: String, checksLoadOrder: Bool) async throws {
        game.effectsWorld.resetHealthCues()
        if SkyrimSaveImport.isImport(slot) {
            try await SkyrimSaveImport.load(slot: slot, game: saveFiles)
            await refreshSaveRows()
            resetPlayTime()
            lastSaveDate = Date()
            return
        }
        if !listings.contains(where: { $0.slot == slot }) {
            await refreshSaveRows()
        }
        let playSeconds = listings.first { $0.slot == slot }?.summary?.summary?.playSeconds
        try await game.runtimeStateWorld.loadSession(slot: slot, checksLoadOrder: checksLoadOrder)
        playSecondsBefore = playSeconds ?? 0
        sessionStart = Date()
        lastSaveDate = Date()
    }

    public func deleteSave(slot: String) async throws {
        guard !SkyrimSaveImport.isImport(slot) else { return }
        try await game.runtimeStateWorld.deleteSave(slot: slot)
        await refreshSaveRows()
    }

    /// A new game counts play time from zero.
    public func resetPlayTime() {
        playSecondsBefore = 0
        sessionStart = Date()
        lastSaveDate = nil
    }

    public func quickload() {
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
    public func requestSave(autosave: Bool) -> Bool {
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

    /// Writes an autosave when the player's settings ask for one. A script's saving lock
    /// skips it without a word.
    public func autosave(_ trigger: AutosaveTrigger) {
        guard !autosavesDisabled, !isSavingDisabled else { return }
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
            } catch SaveFailure.outOfDiskSpace {
                autosavesDisabled = true
                game.hud.showNotification(saveTexts.autosaveDisabled)
            } catch {
                Self.logger
                    .error("[ERROR] autosave: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// The game's kind of failure for a save or load error.
    public static func failure(_ error: any Error) -> any Error {
        switch error {
        case is SaveFailure: error
        case OpenSkySaveStoreError.slotNotFound: SaveFailure.noLongerAvailable
        case is OpenSkySaveError: SaveFailure.corrupt
        case let cocoa as CocoaError where cocoa.code == .fileWriteOutOfSpace:
            SaveFailure.outOfDiskSpace
        case let posix as POSIXError where posix.code == .ENOSPC:
            SaveFailure.outOfDiskSpace
        case let cocoa as CocoaError
            where cocoa.code == .fileReadNoSuchFile || cocoa.code == .fileNoSuchFile:
            SaveFailure.fileNotFound
        case let cocoa as CocoaError where cocoa.isFileError:
            SaveFailure.deviceError
        default: error
        }
    }

    public static func newSlotName(existing: Set<String>) -> String {
        var number = existing.count + 1
        while existing.contains("Save \(number)") {
            number += 1
        }
        return "Save \(number)"
    }

    public var saveTexts: SaveTexts {
        game.worldData.map {
            SaveTexts.resolve(store: $0.gameSettings) { [game] in game.mapWorld.text($0) }
        } ?? .vanilla
    }

    public static func row(
        _ listing: OpenSkySaveSlotListing, texts: SaveTexts = .vanilla
    ) -> SaveSlotRow {
        let summary = listing.summary?.summary
        let savedAt = listing.summary.map {
            Date(timeIntervalSince1970: TimeInterval($0.metadata.creationTimestamp))
        } ?? listing.modified
        let title = summary.map { "\(listing.slot) - \($0.characterName)" } ?? listing.slot
        let detail = summary.map {
            let playTime = SavePlayTime.text(seconds: $0.playSeconds)
            return "\(texts.level) \($0.level), \($0.locationName), \(playTime)"
        } ?? listing.error ?? ""
        let thumbnail = listing.summary?.thumbnail
        return SaveSlotRow(
            slot: listing.slot, title: title, detail: detail, savedAt: savedAt,
            hasThumbnail: thumbnail != nil, error: listing.error,
            character: summary.map {
                SaveSlotCharacter(
                    name: $0.characterName, race: $0.raceName, level: $0.level,
                    playTime: SavePlayTime.text(seconds: $0.playSeconds)
                )
            },
            picture: thumbnail.map {
                SaveSlotPicture(width: $0.width, height: $0.height, rgba: $0.rgba)
            }
        )
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
            let texture = attempt({ try game.renderer?.renderOffscreen(
                width: Self.thumbnailSize.width, height: Self.thumbnailSize.height
            ) })
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

extension SaveGameWorldAdapter: SaveGameWorldPort {}
