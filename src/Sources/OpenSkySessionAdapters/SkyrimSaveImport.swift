// Skyrim saves in the load list. A row's slot is the `.ess` path behind a prefix.
// Loading one runs the import, writes the result as an OpenSky slot, loads that slot
// through the normal restore path, then moves the player to the saved place.
// See docs/engine/ess-import.md.

public import Foundation
import OpenSkyAgentControl
import OpenSkyFormatsCore
import OpenSkyFormatsESS
import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMenusInterface
public import OpenSkySave
import OpenSkySaveInterface
public import OpenSkySessionInterface

/// What `SkyrimSaveImport` reads from the session. `GameViewController` conforms.
@MainActor
public protocol SkyrimSaveImportHost: AnyObject, SendableMetatype {
    var hud: any HUDPort { get }
    var inventory: any InventoryPort { get }
    var menuWorld: any MenuWorldPort { get }
    var runtimeStateWorld: any RuntimeStateWorldPort { get }
}

@MainActor
public enum SkyrimSaveImport {
    nonisolated public static let slotPrefix = "ess:"
    nonisolated public static let titlePrefix = "Skyrim import: "

    nonisolated public static func isImport(_ slot: String) -> Bool {
        slot.hasPrefix(slotPrefix)
    }

    nonisolated public static func slot(for save: URL) -> String {
        slotPrefix + save.path(percentEncoded: false)
    }

    /// The folder setting's saves, or none when it is unset or unreadable.
    public static func rows() async -> [SaveSlotRow] {
        guard let folder = ESSSaveFolderSetting.folder() else { return [] }
        let listings = await attempt { try await ESSSaveFolder(directory: folder).readListings()
        } ??
            []
        return listings.map(row)
    }

    nonisolated public static func row(_ listing: ESSSaveListing) -> SaveSlotRow {
        let header = listing.summary?.header
        let picture = listing.summary.flatMap { ESSSaveFolder.thumbnail(of: $0.screenshot) }
        return SaveSlotRow(
            slot: slot(for: listing.url),
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
    static func load(slot: String, game: any SkyrimSaveImportHost) async throws {
        let url = URL(filePath: String(slot.dropFirst(slotPrefix.count)))
        let file = try await ESSSaveFolder.readFile(at: url)
        let index = try await ESSPluginIndex.load(for: file, root: GameDataLocator.locate())
        let records = ESSPluginRecords(
            index: index, baselines: game.inventory.runtime?.inventory.baselines
        )
        let result = ESSImporter.run(
            file, records: records, appVersion: SaveAppVersion.current
        )
        let written = "Imported " + url.deletingPathExtension().lastPathComponent
        try await game.runtimeStateWorld.writeImported(result.contents, slot: written)
        try await game.runtimeStateWorld.loadSession(slot: written)
        if let target = result.placement.flatMap(teleportTarget) {
            game.menuWorld.teleportPlayer(target, openingRaceMenu: false)
        }
        game.hud.showNotification("Imported \(url.lastPathComponent): \(result.report.summary)")
    }

    /// An interior by its editor ID; an exterior by position in its worldspace.
    nonisolated static func teleportTarget(_ placement: ESSImportedPlacement)
        -> AgentTeleportTarget?
    {
        if placement.isInterior {
            return placement.spaceEditorID.map(AgentTeleportTarget.cell)
        }
        return .position(placement.position, worldspace: placement.spaceEditorID)
    }
}
