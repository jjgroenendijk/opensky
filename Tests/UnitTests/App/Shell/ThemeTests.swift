// Coverage for the Skyrim-inspired shell theme: the display face must resolve
// on any install (bundled Futura Condensed or the system fallback), headings
// carry the uppercase tracked treatment, and the covered game view fully stops
// (owner decision 2026-07-23: no world rendering behind the Asset Browser).

import AppKit
import MetalKit
@testable import opensky
import Testing

struct ThemeTests {
    @Test @MainActor
    func displayFontResolvesAtEverySize() {
        for size: CGFloat in [11, 12, 15, 16] {
            let font = Theme.displayFont(size: size)
            #expect(font.pointSize == size)
        }
    }

    @Test @MainActor
    func headingIsUppercasedAndTracked() {
        let heading = Theme.headingAttributed("Sun shadows", size: 12, color: Theme.gold)
        #expect(heading.string == "SUN SHADOWS")
        var range = NSRange()
        let attributes = heading.attributes(at: 0, effectiveRange: &range)
        #expect(range.length == heading.length)
        #expect(attributes[.foregroundColor] as? NSColor == Theme.gold)
        let kern = attributes[.kern] as? CGFloat
        #expect((kern ?? 0) > 0)
    }

    @Test @MainActor
    func hairlineIsOnePointGoldLayer() {
        let line = Theme.hairline()
        #expect(line.wantsLayer)
        #expect(line.layer?.backgroundColor == Theme.divider.cgColor)
    }
}

@MainActor
struct ShellContentCoverTests {
    /// Covering with a full-content destination must hide the MTKView and stop
    /// its draw loop; returning to a world destination must fully restore it.
    @Test func coveredGameViewIsHiddenAndPaused() throws {
        let content = ShellContentViewController(gameViewController: GameViewController())
        _ = content.view
        let mtkView = try #require(content.gameViewController.view as? MTKView)
        #expect(!mtkView.isHidden)
        #expect(!mtkView.isPaused)

        content.showFullContent(NSViewController())
        #expect(mtkView.isHidden)
        #expect(mtkView.isPaused)

        content.showViewport()
        #expect(!mtkView.isHidden)
        #expect(!mtkView.isPaused)
    }

    /// The frame HUD is an overlay on the game slot, so it must disappear with
    /// the game view a full-content destination covers.
    @Test func frameHUDHidesWhileTheGameViewIsCovered() {
        let key = FrameHUDView.visibilityDefaultsKey
        defer { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set(true, forKey: key)

        let content = ShellContentViewController(gameViewController: GameViewController())
        _ = content.view
        #expect(content.isFrameHUDOnScreen)

        content.showFullContent(NSViewController())
        #expect(!content.isFrameHUDOnScreen)
        #expect(!content.isFrameHUDTicking)
        // Covering does not change the user's choice, only what is on screen.
        #expect(content.isFrameHUDEnabled)

        content.showViewport()
        #expect(content.isFrameHUDOnScreen)
    }

    /// Inspector panels are built on first reveal, not at launch: the shell
    /// caches them like full-content controllers, so adding destinations does
    /// not add launch-time provider graphs.
    @Test func inspectorPanelsAreBuiltOnFirstReveal() throws {
        let content = ShellContentViewController(gameViewController: GameViewController())
        _ = content.view

        // Only the game controller is a child before any inspector is shown.
        let inspectorIDs = DestinationRegistry.worldInspectors.map(\.id)
        #expect(!inspectorIDs.isEmpty, "test needs at least one world inspector")
        #expect(content.children.count == 1)

        let first = try #require(inspectorIDs.first)
        content.showInspector(id: first)
        #expect(content.children.count == 2)

        // Revealing the same destination again reuses the cached panel.
        content.showViewport()
        content.showInspector(id: first)
        #expect(content.children.count == 2)
    }
}
