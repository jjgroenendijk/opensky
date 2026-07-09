// OpenSky entry point. Programmatic AppKit launch — no storyboard, no nib.
// An @main type (not main.swift) so the entry runs MainActor-isolated.

import AppKit

@main
enum OpenSkyApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
