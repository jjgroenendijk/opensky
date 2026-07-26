import AppKit
@testable import opensky
import Testing

struct AppShellOverrideTests {
    @Test @MainActor
    func viewMenuRegistersResetAllOverridesOnResponderChain() throws {
        let menu = AppDelegate.makeViewMenu()
        let item = try #require(
            menu.items.first {
                $0.identifier?.rawValue == "ResetAllOverridesCommand"
            }
        )
        #expect(item.title == "Reset all overrides")
        #expect(item.action == #selector(AppShellViewController.resetAllOverrides(_:)))
        #expect(item.target == nil)
        #expect(item.keyEquivalent.isEmpty)
    }

    @Test @MainActor
    func resetAllDoesNotConstructUnopenedPanels() {
        let content = ShellContentViewController(gameViewController: GameViewController())
        _ = content.view
        #expect(content.cachedPanelIDs.isEmpty)

        content.resetAllOverrides()

        #expect(content.cachedPanelIDs.isEmpty)
    }
}
