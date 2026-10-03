// World > Kill Cam: play any camera shot or a kill cam on the selected actor,
// turn kill cams off, shake the camera, and see which camera paths pass.

import AppKit
import OpenSkyWorld

final class CinematicCameraSection: PanelSectionViewController {
    weak var provider: (any CinematicCameraControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    let shotControl = NSComboBox()
    let playShotControl = NSButton(title: "Play shot", target: nil, action: nil)
    let killCamControl = NSButton(title: "Kill cam", target: nil, action: nil)
    let stopControl = NSButton(title: "Stop", target: nil, action: nil)
    let shakeControl = NSButton(title: "Shake", target: nil, action: nil)
    let enabledControl = NSButton(checkboxWithTitle: "Kill cams", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "CinematicCameraStatsLabel")
    private var shotNames: [String] = []

    override var sectionTitle: String {
        "Kill Cam"
    }

    override var sectionIdentifier: String {
        "killCam"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        shotControl.toolTip = "The camera shot to play from the player toward the nearest actor."
        PanelComponents.configureComboBox(
            shotControl, target: self, action: #selector(playShot),
            identifier: "CameraShotControl", width: 170
        )
        playShotControl.toolTip = "Plays the chosen shot now."
        PanelComponents.configureButton(
            playShotControl, target: self, action: #selector(playShot),
            identifier: "CameraShotPlayControl"
        )
        killCamControl.toolTip = "Plays a kill cam on the nearest actor."
        PanelComponents.configureButton(
            killCamControl, target: self, action: #selector(playKillCam),
            identifier: "KillCamPlayControl"
        )
        PanelComponents.configureButton(
            stopControl, target: self, action: #selector(stop), identifier: "CinematicStopControl"
        )
        shakeControl.toolTip = "Shakes the camera for one second."
        PanelComponents.configureButton(
            shakeControl, target: self, action: #selector(shake), identifier: "CameraShakeControl"
        )
        enabledControl.toolTip = "A killing blow on the last enemy may play a kill cam."
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(toggleEnabled),
            identifier: "KillCamEnabledControl"
        )
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Shot",
                    captionWidth: 60,
                    field: shotControl
                ),
                PanelComponents.buttonRow([
                    playShotControl,
                    killCamControl,
                    stopControl,
                    shakeControl
                ]),
                enabledControl
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        sync(provider?.cinematicSnapshot ?? .unavailable)
    }

    private func sync(_ snapshot: CinematicCameraSnapshot) {
        if snapshot.shotNames != shotNames {
            shotNames = snapshot.shotNames
            shotControl.removeAllItems()
            shotControl.addItems(withObjectValues: shotNames)
        }
        for control in [
            shotControl,
            playShotControl,
            killCamControl,
            stopControl,
            shakeControl,
            enabledControl
        ] {
            control.isEnabled = snapshot.isAvailable
        }
        enabledControl.state = snapshot.killCamsEnabled ? .on : .off
    }

    override func refreshReadout() {
        let snapshot = provider?.cinematicSnapshot ?? .unavailable
        sync(snapshot)
        statsLabel.stringValue = CinematicCameraReadout.text(for: snapshot)
    }

    @objc private func playShot() {
        let name = shotControl.stringValue
        guard !name.isEmpty else { return }
        provider?.playCameraShot(editorID: name)
        finishInteraction()
    }

    @objc private func playKillCam() {
        provider?.playKillCamOnSelected()
        finishInteraction()
    }

    @objc private func stop() {
        provider?.stopCinematicCamera()
        finishInteraction()
    }

    @objc private func shake() {
        provider?.shakeCamera()
        finishInteraction()
    }

    @objc private func toggleEnabled() {
        provider?.killCamsEnabled = enabledControl.state == .on
        finishInteraction()
    }
}
