// The app's top-level windows: the launcher and the game window. Both share
// the dark theme, so a switch between them never flashes a light frame.

import AppKit

enum AppWindows {
    static func makeLauncher(content: NSViewController) -> NSWindow {
        let window = makeWindow(size: NSSize(width: 900, height: 600), content: content)
        window.title = "OpenSky Launcher"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = LauncherStyle.sidebarBackground
        window.setFrameAutosaveName("OpenSkyLauncherWindow")
        return window
    }

    /// The game alone. Full screen is the usual way to play, so the window
    /// offers it; it does not force it.
    static func makePlay(game: GameViewController) -> NSWindow {
        let window = makeWindow(size: NSSize(width: 1280, height: 720), content: game)
        window.title = "OpenSky"
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.setFrameAutosaveName("OpenSkyPlayWindow")
        return window
    }

    private static func makeWindow(size: NSSize, content: NSViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = content
        window.setContentSize(size)
        window.backgroundColor = Theme.windowBackground
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
