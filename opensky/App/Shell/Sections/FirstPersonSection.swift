// World > First person section (issue #190): the arms A/B toggle, the
// first-person field of view, and the readout that says why there are no arms
// when there are none.
//
// It sits under the World destination beside Camera rather than under its own
// destination because it is a knob set for a camera mode the Camera section
// already selects (the placement rule in docs/tools/app-ui.md: a new knob for
// an existing subsystem joins that subsystem's neighbourhood).

import AppKit

final class FirstPersonSection: PanelSectionViewController {
    weak var provider: (any FirstPersonControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let armsEnabledControl = NSButton(
        checkboxWithTitle: "Draw first-person arms", target: nil, action: nil
    )
    let fovControl = NSSlider(value: 65, minValue: 30, maxValue: 120, target: nil, action: nil)
    private let fovValueLabel = PanelComponents.valueLabel(width: 52)
    private let statsLabel = PanelComponents.statsLabel(identifier: "FirstPersonStatsLabel")

    override var sectionTitle: String {
        "First person"
    }

    override var sectionIdentifier: String {
        "first-person"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any FirstPersonControlProviding)?) -> Bool {
        guard let provider else { return false }
        return !provider.firstPersonArmsEnabled
            || provider.firstPersonFOVYDegrees != FirstPersonCamera.defaultFOVYDegrees
    }

    static func resetToDefaults(provider: (any FirstPersonControlProviding)?) {
        provider?.firstPersonArmsEnabled = true
        provider?.firstPersonFOVYDegrees = FirstPersonCamera.defaultFOVYDegrees
    }

    /// Current readout text; the verification-surface tests read it directly.
    var statsReadout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            armsEnabledControl, target: self, action: #selector(armsEnabledChanged),
            identifier: "FirstPersonArmsEnabledControl"
        )
        PanelComponents.configureSlider(
            fovControl, target: self, action: #selector(fovChanged),
            identifier: "FirstPersonFOVControl", width: 180
        )
        fovControl.minValue = Double(
            MatrixMath.degrees(fromRadians: FirstPersonCamera.fovYRange.lowerBound)
        )
        fovControl.maxValue = Double(
            MatrixMath.degrees(fromRadians: FirstPersonCamera.fovYRange.upperBound)
        )
        return [
            PanelComponents.group([
                armsEnabledControl,
                PanelComponents.caption("Vertical field of view"),
                PanelComponents.sliderRow(slider: fovControl, valueLabel: fovValueLabel)
            ]),
            PanelComponents.note(
                "No readable game data names a first-person field of view: "
                    + "Skyrim.esm declares no FOV setting and the shipped "
                    + "Skyrim_Default.ini carries no FOV key, so this is an "
                    + "OpenSky setting defaulting to the world value."
            ),
            statsLabel
        ]
    }

    override func syncControls() {
        armsEnabledControl.isEnabled = provider != nil
        fovControl.isEnabled = provider != nil
        guard let provider else { return }
        armsEnabledControl.state = provider.firstPersonArmsEnabled ? .on : .off
        fovControl.floatValue = provider.firstPersonFOVYDegrees
        updateFOVLabel(provider.firstPersonFOVYDegrees)
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "First person: unavailable"
            return
        }
        let snapshot = provider.firstPersonSnapshot
        guard snapshot.rendererAvailable else {
            statsLabel.stringValue = "First person: no renderer"
            return
        }
        statsLabel.stringValue = Self.readout(snapshot)
    }

    /// The readout text for one snapshot. Static and pure so a unit test can
    /// assert the exact lines without an AppKit view (issue #190).
    static func readout(_ snapshot: FirstPersonSnapshot) -> String {
        var lines = [
            "Arms: \(snapshot.active ? "drawn" : "not drawn")",
            "Graph: \(snapshot.graphAttached ? "attached" : "none")"
                + "  updates: \(snapshot.graphUpdates)",
            "Rig: \(snapshot.rigAttached ? "attached" : "none")"
                + "  meshes: \(snapshot.armModelCount)"
                + "  dropped: \(snapshot.droppedPieceCount)",
            snapshot.hasCameraBone
                ? String(
                    format: "Camera bone: %@ at z %.1f",
                    FirstPersonCamera.cameraBoneName,
                    snapshot.cameraBoneHeight ?? FirstPersonCamera.fallbackCameraBoneHeight
                )
                : "Camera bone: absent (arms hang off the reference height)",
            String(format: "Field of view: %.0f deg", snapshot.fovYDegrees)
        ]
        if let reason = snapshot.failureReason {
            lines.append("No arms: \(reason)")
        }
        if !snapshot.missingVariables.isEmpty {
            lines.append("Unbound variables: \(snapshot.missingVariables.joined(separator: ", "))")
        }
        if !snapshot.missingEvents.isEmpty {
            lines.append("Unbound events: \(snapshot.missingEvents.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    private func updateFOVLabel(_ degrees: Float) {
        fovValueLabel.stringValue = String(format: "%.0f deg", degrees)
    }

    @objc private func armsEnabledChanged() {
        provider?.firstPersonArmsEnabled = armsEnabledControl.state == .on
        finishInteraction()
    }

    @objc private func fovChanged() {
        let degrees = fovControl.floatValue
        provider?.firstPersonFOVYDegrees = degrees
        updateFOVLabel(degrees)
        finishInteraction()
    }
}
