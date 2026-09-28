// OpenSky entry point. Programmatic AppKit launch — no storyboard, no nib.
// An @main type (not main.swift) so the entry runs MainActor-isolated.

import AppKit

@main
enum OpenSkyApp {
    static func main() {
        let app = NSApplication.shared

        // Unit tests inject into this process (TEST_HOST) and only need it
        // alive — no delegate, so no window/renderer; .prohibited keeps it out
        // of the Dock. XCUITest-launched instances lack this variable and get
        // the full app.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            app.setActivationPolicy(.prohibited)
            app.run()
            return
        }

        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
