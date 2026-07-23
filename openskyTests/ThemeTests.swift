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
}
