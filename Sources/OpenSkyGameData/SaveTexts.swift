// The words of the save and load pages and their progress lines, from the `sSave*`,
// `sMenuDisplay*`, and related string settings. See docs/engine/system-menu.md.

import OpenSkyFormatsESM

nonisolated public struct SaveTexts: Equatable, Sendable {
    public var quickSaving = "Saving"
    public var saved = "Saved"
    public var quickSaved = "Quicksave"
    public var loading = "Loading"
    public var deleted = "Deleted"
    public var saveFailed = "Failed:"
    public var newSave = "New Save"
    /// `%s` is the save's title; the game's own question names no save.
    public var overwriteQuestion = "Save over %s?"
    public var deleteQuestion = "Delete %s?"
    public var level = "Level"
    public var unknownLocation = "Unknown"
    /// The name of an exterior cell without one of its own.
    public var wilderness = "Exterior"

    public static let vanilla = Self()

    public init() {}

    public static func resolve(
        store: GameSettingStore, text: (LString) -> String? = { _ in nil }
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
        return texts
    }
}
