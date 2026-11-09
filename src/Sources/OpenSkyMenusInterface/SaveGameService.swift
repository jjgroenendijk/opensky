import Foundation
public import OpenSkyGameData

/// Saving and loading for the Save and Load pages and the quick keys. The file work
/// runs off the main actor; game state is read and applied on it.
public protocol SaveGameService: AnyObject {
    /// The newest listing read, empty before the first.
    var saveRows: [SaveSlotRow] { get }
    @discardableResult
    func refreshSaveRows() async -> [SaveSlotRow]
    /// Writes `slot`, or a new slot when nil; returns the slot written.
    func saveGame(slot: String?) async throws -> String
    func loadGame(slot: String) async throws
    func deleteSave(slot: String) async throws
    /// Writes the session as a Skyrim save under a new name; returns the file name.
    func exportSkyrimSave() async throws -> String
    /// The words the save pages and progress lines use.
    var saveTexts: SaveTexts { get }
    /// `SetInChargen` turned saving off.
    var isSavingDisabled: Bool { get }
    /// Loads `slot` even though the load order changed since it was written, after the
    /// player answered `sSaveGameContentIsMissing`.
    func loadGame(slot: String, acceptingChangedContent: Bool) async throws
}

extension SaveGameService {
    public var saveTexts: SaveTexts {
        .vanilla
    }

    public var isSavingDisabled: Bool {
        false
    }

    public func loadGame(slot: String, acceptingChangedContent _: Bool) async throws {
        try await loadGame(slot: slot)
    }

    public func exportSkyrimSave() async throws -> String {
        throw CocoaError(.featureUnsupported)
    }
}
