// The one game-folder picker. The launcher and Settings both use it, so a
// chosen folder is validated and saved the same way everywhere.

import AppKit
import OpenSkyGameData

enum GameFolderPicker {
    /// Shows a folder sheet and saves a valid choice. After a choice,
    /// `completion` gets nil when saved, or the problem with the folder.
    static func choose(for window: NSWindow, completion: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message =
            "Select the Skyrim Special Edition install folder (contains Data/Skyrim.esm)."
        panel.prompt = "Use Folder"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            completion(save(path: url.path(percentEncoded: false)))
        }
    }

    /// Returns nil when saved, or the problem with the folder.
    static func save(path: String) -> String? {
        do {
            try GameDataLocator.saveUserChoice(path: path)
            return nil
        } catch {
            return "Not a Skyrim SE install: \(path) — "
                + "expected a folder containing Data/Skyrim.esm."
        }
    }
}
