// Skyrim saves in the load list. A row's slot is the `.ess` path behind a prefix.
// Loading one runs the import, writes the result as an OpenSky slot, loads that slot
// through the normal restore path, then moves the player to the saved place.
// See docs/engine/ess-import.md.

import Foundation
import OpenSkyAgentControl
import OpenSkyFormatsESS
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMenus
import OpenSkySave

@MainActor
enum SkyrimSaveImportAdapter {
    nonisolated static let slotPrefix = "ess:"
    nonisolated static let titlePrefix = "Skyrim import: "

    nonisolated static func isImport(_ slot: String) -> Bool {
        slot.hasPrefix(slotPrefix)
    }

    /// The folder setting's saves, or none when it is unset or unreadable.
    static func rows() async -> [SaveSlotRow] {
        guard let folder = ESSSaveFolderSetting.folder() else { return [] }
        let listings = await (try? ESSSaveFolder(directory: folder).readListings()) ?? []
        return listings.map(row)
    }

    nonisolated static func row(_ listing: ESSSaveListing) -> SaveSlotRow {
        let header = listing.summary?.header
        let picture = listing.summary.flatMap { ESSSaveFolder.thumbnail(of: $0.screenshot) }
        return SaveSlotRow(
            slot: slotPrefix + listing.url.path(percentEncoded: false),
            title: titlePrefix + listing.name + (header.map { " - \($0.playerName)" } ?? ""),
            detail: header.map { "Level \($0.playerLevel), \($0.playerLocation)" }
                ?? listing.error ?? "",
            savedAt: listing.modified, hasThumbnail: picture != nil, error: listing.error,
            character: header.map {
                SaveSlotCharacter(
                    name: $0.playerName, race: $0.playerRaceEditorID,
                    level: Int($0.playerLevel), playTime: ""
                )
            },
            picture: picture
                .map { SaveSlotPicture(width: $0.width, height: $0.height, rgba: $0.rgba) },
            isImport: true
        )
    }

    /// The written slot is named for the save, so importing it again replaces it.
    static func load(slot: String, game: GameViewController) async throws {
        let url = URL(filePath: String(slot.dropFirst(slotPrefix.count)))
        let file = try await ESSSaveFolder.readFile(at: url)
        let index = try await ESSPluginIndex.load(for: file, root: GameDataLocator.locate())
        let records = ESSPluginRecords(
            index: index, baselines: game.inventory.runtime?.inventory.baselines
        )
        let result = ESSImporter.run(
            file, records: records, appVersion: RuntimeStateWorldAdapter.saveAppVersion
        )
        let written = "Imported " + url.deletingPathExtension().lastPathComponent
        try await game.runtimeStateWorld.writeImported(result.contents, slot: written)
        try await game.runtimeStateWorld.loadSession(slot: written)
        if let target = result.placement.flatMap(teleportTarget) {
            game.menuWorld.teleportPlayer(target, openingRaceMenu: false)
        }
        game.hud.showNotification("Imported \(url.lastPathComponent): \(result.report.summary)")
    }

    /// An interior by its editor ID; an exterior by position, in the current worldspace.
    nonisolated static func teleportTarget(_ placement: ESSImportedPlacement)
        -> AgentTeleportTarget?
    {
        if placement.isInterior {
            return placement.spaceEditorID.map(AgentTeleportTarget.cell)
        }
        return .position(placement.position)
    }
}
