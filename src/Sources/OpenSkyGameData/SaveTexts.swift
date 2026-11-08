// The words of the save and load pages and their progress lines, from the `sSave*`,
// `sMenuDisplay*`, and related string settings. See docs/engine/system-menu.md.

/// Why a save or a load did not happen, as the game words it.
nonisolated public enum SaveFailure: Error, Equatable, Sendable {
    /// The file does not decode.
    case corrupt
    /// The slot's file is gone.
    case noLongerAvailable
    /// The load order changed since the save; the game asks before it loads.
    case contentMissing
    /// None of the save's plugins is loaded now.
    case noMasterFiles
    /// The disk is full.
    case outOfDiskSpace
    /// Any other file error.
    case deviceError
    /// A Skyrim save picked for import has gone.
    case fileNotFound
}

nonisolated public struct SaveTexts: Equatable, Sendable {
    public var quickSaving = "Saving"
    public var saved = "Saved"
    public var quickSaved = "Quicksave"
    public var loading = "Loading"
    public var deleted = "Deleted"
    public var saveFailed = "Failed:"
    public var newSave = "New Save"
    /// OpenSky's own row; the game has no export.
    public var exportSkyrim = "Export to Skyrim"
    /// `%s` is the save's title; the game's own question names no save.
    public var overwriteQuestion = "Save over %s?"
    public var deleteQuestion = "Delete %s?"
    public var level = "Level"
    public var unknownLocation = "Unknown"
    /// The name of an exterior cell without one of its own.
    public var wilderness = "Exterior"
    /// `SetInChargen` turned saving off.
    public var cannotSaveNow = "You cannot save right now."
    /// The quick keys while a menu pauses the game.
    public var cannotQuickSave = "You can't Quicksave while the game is paused."
    public var cannotQuickLoad = "You can't Quickload while the game is paused."
    /// An autosave found the disk full and turns autosaves off for the session.
    public var autosaveDisabled = "Save location full. Disabling Autosave."
    public var corruptInGame = "The save game is corrupt. Returning to game."
    public var corruptFromMenu = "The save game is corrupt and cannot be loaded."
    public var noLongerAvailable = "The save game is no longer available. Returning to game."
    public var contentMissing = "This save relies on content that is no longer present. "
        + "Some objects may no longer be available. Continue Loading?"
    public var noMasterFiles = "None of the master files used in this save game are loaded."
    public var outOfDiskSpace = "There is not enough space to save."
    public var deviceError = "The save/load operation failed."
    public var fileNotFound = "File does not exist"
    /// The load list of the main menu when there is no save.
    public var noSavesRow = "[NO SAVES FOUND]"
    /// Continue or Load on the main menu with no save to load.
    public var noSavesNotice = "No saved games."

    public static let vanilla = Self()

    public init() {}

    public static func resolve(
        store: GameSettingStore, text: GameTextResolver = { _ in nil }
    ) -> Self {
        var texts = vanilla
        store.read("sQuickSaving", into: &texts, \.quickSaving, text: text)
        store.read("sSaveSuccessful", into: &texts, \.saved, text: text)
        store.read("sSaveSuccessful", into: &texts, \.quickSaved, text: text)
        store.read("sLoading", into: &texts, \.loading, text: text)
        store.read("sDeleteSuccessful", into: &texts, \.deleted, text: text)
        store.read("sSaveFailed", into: &texts, \.saveFailed, text: text)
        store.read("sMenuDisplayNewSave", into: &texts, \.newSave, text: text)
        store.read("sSaveOverSaveGame", into: &texts, \.overwriteQuestion, text: text)
        store.read("sDeleteSaveGame", into: &texts, \.deleteQuestion, text: text)
        store.read("sMenuDisplayLevelString", into: &texts, \.level, text: text)
        store.read("sMenuDisplayUnknownLocationString", into: &texts, \.unknownLocation, text: text)
        store.read("sDefaultCellName", into: &texts, \.wilderness, text: text)
        let failures: [(String, WritableKeyPath<Self, String>)] = [
            ("sCantSaveNow", \.cannotSaveNow), ("sCantQuickSave", \.cannotQuickSave),
            ("sCantQuickLoad", \.cannotQuickLoad),
            ("sAutoSaveDisabledDueToLackOfSpace", \.autosaveDisabled),
            ("sSaveGameIsCorrupt", \.corruptInGame),
            ("sSaveGameCorruptMenuMessage", \.corruptFromMenu),
            ("sSaveGameNoLongerAvailable", \.noLongerAvailable),
            ("sSaveGameContentIsMissing", \.contentMissing),
            ("sSaveGameNoMasterFilesFound", \.noMasterFiles),
            ("sSaveGameOutOfDiskSpace", \.outOfDiskSpace),
            ("sSaveGameDeviceError", \.deviceError), ("sFileNotFound", \.fileNotFound),
            ("sNoSaves", \.noSavesRow), ("sMenuDisplayNoSaves", \.noSavesNotice)
        ]
        for (editorID, keyPath) in failures {
            store.read(editorID, into: &texts, keyPath, text: text)
        }
        return texts
    }

    /// The message for `failure`. A corrupt save names where the player goes next: back to
    /// the game, or nowhere from the main menu.
    public func text(for failure: SaveFailure, fromMainMenu: Bool = false) -> String {
        switch failure {
        case .corrupt: fromMainMenu ? corruptFromMenu : corruptInGame
        case .noLongerAvailable: noLongerAvailable
        case .contentMissing: contentMissing
        case .noMasterFiles: noMasterFiles
        case .outOfDiskSpace: outOfDiskSpace
        case .deviceError: deviceError
        case .fileNotFound: fileNotFound
        }
    }
}
