// Developer > Rendering Performance > Room Culling: the interior room-and-portal
// switch, and how many rooms the camera sees and instances they skip.

import AppKit
import OpenSkyRendering

final class RoomCullingSection: PanelSectionViewController {
    weak var provider: (any RenderPerformanceControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(checkboxWithTitle: "Cull hidden rooms", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "RoomCullingStatsLabel")

    override var sectionTitle: String {
        "Room Culling"
    }

    override var sectionIdentifier: String {
        "roomCulling"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any RenderPerformanceControlProviding)?) -> Bool {
        provider?.roomCullingEnabled == false
    }

    static func resetToDefaults(provider: (any RenderPerformanceControlProviding)?) {
        provider?.roomCullingEnabled = true
    }

    var statsReadout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        enabledControl.toolTip = "Inside, skips rooms the camera cannot see through a doorway."
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(enabledChanged),
            identifier: "RoomCullingEnabledControl"
        )
        return [enabledControl, statsLabel]
    }

    override func syncControls() {
        enabledControl.isEnabled = provider != nil
        enabledControl.state = provider?.roomCullingEnabled == true ? .on : .off
    }

    override func refreshReadout() {
        guard let readout = provider?.renderPerformanceSnapshot?.roomCulling else {
            statsLabel.stringValue = "Rooms: unavailable"
            return
        }
        statsLabel.stringValue = Self.text(readout)
    }

    static func text(_ readout: RoomCullingReadout) -> String {
        guard readout.rooms > 0 else { return "Rooms: none" }
        let seen = readout.visibleRooms.map { "\($0) seen" } ?? "all drawn"
        return "Rooms: \(readout.rooms), portals: \(readout.portals), \(seen), "
            + "instances culled: \(readout.culledInstances)"
    }

    @objc private func enabledChanged() {
        provider?.roomCullingEnabled = enabledControl.state == .on
        finishInteraction()
    }
}
