// Writes the session as a Skyrim `.ess` in the saves folder setting. Each export gets a
// new file name, so a save the game wrote is never replaced. The mapping lives in
// `ESSExporter`. See docs/engine/ess-export.md.

import Foundation
import OpenSkyFormatsESS
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMenus
import OpenSkyProgression
import OpenSkySave
import OpenSkyWorld
import OpenSkyWorldState

nonisolated enum SkyrimSaveExportError: Error, LocalizedError {
    case noSavesFolder

    var errorDescription: String? {
        switch self {
        case .noSavesFolder: "No Skyrim saves folder is set."
        }
    }
}

/// What `SkyrimSaveExportAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol SkyrimSaveExportHost: AnyObject {
    var hud: HUDCoordinator { get }
    var inventory: InventoryCoordinator { get }
    var progression: ProgressionCoordinator { get }
    var runtimeState: RuntimeStateCoordinator { get }
}

@MainActor
enum SkyrimSaveExportAdapter {
    /// Reads the plugins off the main actor, then encodes and writes the file.
    static func export(
        _ contents: OpenSkySaveContents, game: any SkyrimSaveExportHost
    ) async throws -> (url: URL, report: ESSExportReport) {
        guard let directory = ESSSaveFolderSetting.folder() else {
            throw SkyrimSaveExportError.noSavesFolder
        }
        let folder = ESSSaveFolder(directory: directory)
        let root = try GameDataLocator.locate()
        let index = await ESSPluginIndex.load(forExport: contents, root: root)
        let records = ESSPluginRecords(
            index: index, baselines: game.inventory.runtime?.inventory.baselines
        )
        let header = ESSExportHeader(
            saveNumber: UInt32((try? folder.saveURLs().count) ?? 0) + 1,
            gameDate: gameDate(contents.clock ?? GameClock(), game: game),
            experienceForNextLevel: game.progression.leveling?.experienceForNextLevel ?? 0,
            savedAt: Date()
        )
        let result = try ESSExporter.run(contents, records: records, header: header)
        let url = try await folder.writeExport(result.data)
        game.hud.showNotification("Exported \(url.lastPathComponent): \(result.report.summary)")
        return (url, result.report)
    }

    /// The date line the game's own menus show, which the load list prints.
    private static func gameDate(_ clock: GameClock, game: any SkyrimSaveExportHost) -> String {
        game.runtimeState.calendarTexts.dateLine(
            weekday: clock.weekday, hourOfDay: clock.hourOfDay,
            day: clock.day, month: clock.month, year: clock.year
        )
    }
}
