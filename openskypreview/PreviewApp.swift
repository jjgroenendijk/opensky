// Asset preview GUI entry point (todo 2.10): third product target sharing
// the engine sources — browse the VFS and preview single assets from the
// user's own install (read-only external input, AGENTS.md Legal & IP).
// Programmatic AppKit launch, no storyboard — matches the main app.

import AppKit

@main
enum PreviewApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = PreviewAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
