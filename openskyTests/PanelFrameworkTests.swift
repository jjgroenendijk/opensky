// Coverage for the shared inspector-panel framework (issue #98): the readout
// ticker's start/stop lifecycle, collapsible-section reveal + persistence, and
// the scrolling panel document starting at the top.

import AppKit
@testable import opensky
import Testing

private final class DirectPanel: InspectorPanelViewController {
    let marker = NSTextField(labelWithString: "marker")

    override func makeContentViews() -> [NSView] {
        marker.setAccessibilityIdentifier("DirectPanelMarker")
        return [marker]
    }
}

struct PanelFrameworkTests {
    @Test @MainActor
    func tickerStartsIdempotentlyAndStops() {
        let ticker = InspectionTicker()
        #expect(!ticker.isActive)
        ticker.start {}
        #expect(ticker.isActive)
        ticker.start {} // second start must not schedule a second timer
        #expect(ticker.isActive)
        ticker.stop()
        #expect(!ticker.isActive)
    }

    @Test @MainActor
    func collapsibleSectionTogglesContent() {
        let content = NSView()
        let section = CollapsibleSectionView(
            title: "Grass", identifier: "test-toggle", content: content
        )
        defer { UserDefaults.standard.removeObject(forKey: "panelSection.expanded.test-toggle") }

        #expect(section.isExpanded) // default expanded
        #expect(!content.isHidden)
        section.setExpanded(false)
        #expect(!section.isExpanded)
        #expect(content.isHidden)
        section.setExpanded(true)
        #expect(!content.isHidden)
    }

    @Test @MainActor
    func collapsibleSectionPersistsCollapsedState() {
        let id = "test-persist"
        let key = "panelSection.expanded.\(id)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let first = CollapsibleSectionView(title: "Grass", identifier: id, content: NSView())
        first.setExpanded(false)

        // A fresh view with the same id restores the stored collapsed state.
        let restored = CollapsibleSectionView(title: "Grass", identifier: id, content: NSView())
        #expect(!restored.isExpanded)
    }

    @Test @MainActor
    func directContentPanelScrollDocumentStartsAtTop() throws {
        let panel = DirectPanel()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        panel.view.layoutSubtreeIfNeeded()

        let document = try #require(scrollView.documentView)
        #expect(document.frame.height > 0)
        // Flipped document: the first control sits near the top (small y).
        let markerInDoc = panel.marker.convert(panel.marker.bounds, to: document)
        #expect(markerInDoc.minY < 60, "marker not near top: \(markerInDoc)")
        #expect(document.bounds.intersects(markerInDoc))
    }
}
