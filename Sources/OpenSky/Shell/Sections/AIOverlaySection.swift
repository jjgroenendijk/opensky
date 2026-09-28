// World > AI & Navigation > Overlays section (issue #422, roadmap item 16.3;
// shipped by the M16 gate, issue #203): the three world-space debug overlays and
// what the overlay pass drew for them.
//
// Three checkboxes rather than one, because they answer three different
// questions and a user watching a guard walk to an inn wants the corridor
// without the whole navmesh under it. All three default off, which makes this
// the one section under the destination that carries overridden-ness: the
// sidebar's "Reset all" switches them back off, exactly as it releases a frozen
// physics simulation, and a session left with the navmesh drawn over Whiterun
// otherwise reads as a rendering bug rather than as a control someone left on.

import AppKit

final class AIOverlaySection: PanelSectionViewController {
    weak var provider: (any AIOverlayControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let navmeshControl = NSButton(
        checkboxWithTitle: "Draw navmesh triangles", target: nil, action: nil
    )
    let pathControl = NSButton(
        checkboxWithTitle: "Draw the current path", target: nil, action: nil
    )
    let detectionControl = NSButton(
        checkboxWithTitle: "Draw detection cones", target: nil, action: nil
    )

    private let statsLabel = PanelComponents.statsLabel(identifier: "AIOverlayStatsLabel")

    override var sectionTitle: String {
        "Overlays"
    }

    override var sectionIdentifier: String {
        "aiOverlays"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    var readout: String {
        statsLabel.stringValue
    }

    /// All three overlays default off, so any one of them being on is this
    /// destination's notion of a non-default value.
    static func isOverridden(provider: (any AIOverlayControlProviding)?) -> Bool {
        guard let provider else { return false }
        let snapshot = provider.aiOverlaySnapshot
        return snapshot.navmeshOverlayEnabled
            || snapshot.pathOverlayEnabled
            || snapshot.detectionOverlayEnabled
    }

    static func resetToDefaults(provider: (any AIOverlayControlProviding)?) {
        provider?.navmeshOverlayEnabled = false
        provider?.pathOverlayEnabled = false
        provider?.detectionOverlayEnabled = false
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            navmeshControl, target: self, action: #selector(navmeshChanged),
            identifier: "AINavmeshOverlayControl"
        )
        PanelComponents.configureCheckbox(
            pathControl, target: self, action: #selector(pathChanged),
            identifier: "AIPathOverlayControl"
        )
        PanelComponents.configureCheckbox(
            detectionControl, target: self, action: #selector(detectionChanged),
            identifier: "AIDetectionOverlayControl"
        )
        return [
            PanelComponents.note(
                "The navmesh overlay fills every walkable triangle in the streamed cells, "
                    + "one colour per cell. The path overlay highlights the corridor of the "
                    + "most recent successful query and draws its waypoints. The detection "
                    + "overlay draws each observer's view cone and a line to whatever it "
                    + "currently perceives. All three are drawn after the scene with "
                    + "read-only depth, so they sit on the world rather than through it."
            ),
            PanelComponents.group([navmeshControl, pathControl, detectionControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        for control in [navmeshControl, pathControl, detectionControl] {
            control.isEnabled = available
        }
        guard let snapshot = provider?.aiOverlaySnapshot else { return }
        navmeshControl.state = snapshot.navmeshOverlayEnabled ? .on : .off
        pathControl.state = snapshot.pathOverlayEnabled ? .on : .off
        detectionControl.state = snapshot.detectionOverlayEnabled ? .on : .off
    }

    override func refreshReadout() {
        guard let snapshot = provider?.aiOverlaySnapshot else {
            statsLabel.stringValue = "Overlays: unavailable"
            return
        }
        statsLabel.stringValue = [
            AIOverlayReadout.toggleText(for: snapshot),
            AIOverlayReadout.drawText(for: snapshot)
        ].joined(separator: "\n")
    }

    // MARK: - Actions

    @objc private func navmeshChanged() {
        provider?.navmeshOverlayEnabled = navmeshControl.state == .on
        finishInteraction()
    }

    @objc private func pathChanged() {
        provider?.pathOverlayEnabled = pathControl.state == .on
        finishInteraction()
    }

    @objc private func detectionChanged() {
        provider?.detectionOverlayEnabled = detectionControl.state == .on
        finishInteraction()
    }
}
