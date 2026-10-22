// World > Player & Locomotion > Mount section: the player's horse or dragon, with
// mount and dismount buttons (docs/engine/riding.md).

import AppKit
import OpenSkyPlayer

final class LocomotionMountSection: PanelSectionViewController {
    weak var provider: (any MountControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    let mountNearestControl = NSButton(title: "Mount nearest", target: nil, action: nil)
    let dismountControl = NSButton(title: "Dismount", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "LocomotionMountStatsLabel")

    override var sectionTitle: String {
        "Mount"
    }

    override var sectionIdentifier: String {
        "locomotionMount"
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureButton(
            mountNearestControl, target: self, action: #selector(mountNearest),
            identifier: "LocomotionMountNearestControl"
        )
        mountNearestControl.toolTip = "Mount the nearest horse, or a dragon the player may ride."
        PanelComponents.configureButton(
            dismountControl, target: self, action: #selector(dismount),
            identifier: "LocomotionDismountControl"
        )
        dismountControl.toolTip = "Get off the mount."
        return [PanelComponents.buttonRow([mountNearestControl, dismountControl]), statsLabel]
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Mount: unavailable"
            return
        }
        statsLabel.stringValue = provider.mountSnapshot.text
    }

    @objc private func mountNearest() {
        provider?.mountNearest()
        finishInteraction()
    }

    @objc private func dismount() {
        provider?.dismountPlayer()
        finishInteraction()
    }
}
