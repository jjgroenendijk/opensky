// Toolbar screenshot flow (issue #98 PR 2), moved out of the old
// MainViewController: save panel -> offscreen render of the live World camera
// via GameViewController.writeScreenshot(to:) -> transient "Saved" button
// state, or an action-scoped error sheet.

import AppKit
import UniformTypeIdentifiers

@MainActor
final class ScreenshotCoordinator {
    private static let idleTitle = "Screenshot…"

    /// Runs the save-panel flow against the current game controller. The
    /// caller gates on a world destination being active (the toolbar button is
    /// disabled otherwise).
    func saveScreenshot(
        from game: GameViewController,
        window: NSWindow,
        button: NSButton?
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = Self.defaultScreenshotName()
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try game.writeScreenshot(to: url)
                Self.flashSaved(on: button)
            } catch {
                let alert = NSAlert(error: error)
                alert.beginSheetModal(for: window)
            }
        }
    }

    private static func defaultScreenshotName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "OpenSky-\(formatter.string(from: Date())).png"
    }

    private static func flashSaved(on button: NSButton?) {
        button?.title = "Saved"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            button?.title = idleTitle
        }
    }
}
