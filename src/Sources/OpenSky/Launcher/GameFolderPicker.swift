// The one game-folder picker. The launcher and Settings both use it, so a
// chosen folder is validated and saved the same way everywhere.

import AppKit
import OpenSkyGameData

enum GameFolderPicker {
    static let defaultMessage =
        "Choose the Skyrim Special Edition folder. It holds Data/Skyrim.esm."

    /// Asks again after a folder that is not an install, until a valid choice or Cancel.
    /// `saved` runs once a valid choice is saved.
    static func chooseUntilValid(
        for window: NSWindow,
        message: String = defaultMessage,
        saved: @escaping () -> Void
    ) {
        choose(for: window, message: message) { problem in
            guard let problem else {
                saved()
                return
            }
            chooseUntilValid(for: window, message: problem, saved: saved)
        }
    }

    /// Shows a folder sheet and saves a valid choice. After a choice,
    /// `completion` gets nil when saved, or the problem with the folder.
    static func choose(
        for window: NSWindow,
        message: String = defaultMessage,
        completion: @escaping (String?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = "Use Folder"
        panel.directoryURL = startFolder()
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            completion(save(path: url.path(percentEncoded: false)))
        }
    }

    /// Steam's game folder when it exists, so the user starts one step from the install.
    private static func startFolder() -> URL? {
        let common = GameDataLocator.defaultSteamInstallURL.deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: common.path) ? common : nil
    }

    /// Returns nil when saved, or the problem with the folder.
    static func save(path: String) -> String? {
        do {
            try GameDataLocator.saveUserChoice(path: path)
            return nil
        } catch {
            return "No Skyrim Special Edition in \(path). "
                + "Choose the folder that holds Data/Skyrim.esm."
        }
    }
}
