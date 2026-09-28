import AppKit
@testable import opensky
import Testing

struct SettingsWindowControllerTests {
    @Test @MainActor
    func localizationControlsFitInsideSettingsWindow() throws {
        let controller = SettingsWindowController()
        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()

        for identifier in [
            "SettingsLanguageControl",
            "SettingsLanguageStatsLabel",
            "SettingsApplyLanguageControl",
            "SettingsResetLanguageControl"
        ] {
            let view = try #require(find(identifier: identifier, in: contentView))
            #expect(view.frame.minY >= contentView.bounds.minY)
            #expect(view.frame.maxY <= contentView.bounds.maxY)
        }
    }

    @MainActor
    private func find(identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier {
            return view
        }
        for subview in view.subviews {
            if let found = find(identifier: identifier, in: subview) {
                return found
            }
        }
        return nil
    }
}
