// Toolbar screenshot flow: save panel, a copy of the next frame the window
// presents through `GameViewController.writeScreenshot(to:)`, then a "Saved"
// state or an error sheet.

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
            Task {
                do {
                    try await game.writeScreenshot(to: url)
                    Self.flashSaved(on: button)
                } catch {
                    let alert = NSAlert(error: error)
                    alert.beginSheetModal(for: window) { _ in }
                }
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
        Task { [weak button] in
            try? await Task.sleep(for: .seconds(1.2))
            button?.title = idleTitle
        }
    }
}
