// World > HUD & Interaction > Face Morphs (issue #207): select one named TRI
// target and scrub its actor-local 0...1 weight while inspecting association
// paths and misses.

import AppKit

final class FaceMorphSection: PanelSectionViewController {
    weak var provider: (any FaceMorphControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let targetControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let weightControl = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let resetControl = NSButton(title: "Reset weights", target: nil, action: nil)
    private let weightLabel = PanelComponents.valueLabel(width: 64)
    private let statsLabel = PanelComponents.statsLabel(identifier: "FaceMorphStatsLabel")

    override var sectionTitle: String {
        "Face Morphs"
    }

    override var sectionIdentifier: String {
        "faceMorphs"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    static func isOverridden(provider: (any FaceMorphControlProviding)?) -> Bool {
        provider?.faceMorphSnapshot.weights.values.contains(where: { $0 != 0 }) ?? false
    }

    static func resetToDefaults(provider: (any FaceMorphControlProviding)?) {
        provider?.resetFaceMorphWeights()
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configurePopUp(
            targetControl,
            target: self,
            action: #selector(targetChanged),
            identifier: "FaceMorphTargetControl",
            width: PanelMetrics.contentWidth
        )
        PanelComponents.configureSlider(
            weightControl,
            target: self,
            action: #selector(weightChanged),
            identifier: "MorphWeightControl",
            width: 200
        )
        PanelComponents.configureButton(
            resetControl,
            target: self,
            action: #selector(resetWeights),
            identifier: "FaceMorphResetControl"
        )
        return [
            PanelComponents.note(
                "Uses the open dialogue speaker, or the actor under the crosshair. "
                    + "Weights compose per actor and never change the cached face mesh."
            ),
            PanelComponents.group([
                targetControl,
                PanelComponents.sliderRow(slider: weightControl, valueLabel: weightLabel),
                resetControl
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let snapshot = provider?.faceMorphSnapshot ?? .empty
        let selected = targetControl.titleOfSelectedItem
        if targetControl.itemTitles != snapshot.targetNames {
            targetControl.removeAllItems()
            targetControl.addItems(withTitles: snapshot.targetNames)
        }
        if let selected, snapshot.targetNames.contains(selected) {
            targetControl.selectItem(withTitle: selected)
        } else if !snapshot.targetNames.isEmpty {
            targetControl.selectItem(at: 0)
        }
        let target = targetControl.titleOfSelectedItem ?? ""
        weightControl.floatValue = snapshot.weights[target] ?? 0
        let available = snapshot.actor != nil && !snapshot.targetNames.isEmpty
        targetControl.isEnabled = available
        weightControl.isEnabled = available
        resetControl.isEnabled = snapshot.actor != nil
        updateWeightLabel()
    }

    override func refreshReadout() {
        syncControls()
        let snapshot = provider?.faceMorphSnapshot ?? .empty
        guard let actor = snapshot.actor else {
            statsLabel.stringValue = "Face morphs: no selected actor"
            return
        }
        let active = snapshot.weights.values.filter { $0 > 0 }.count
        var lines = [
            "Actor \(actor) · \(snapshot.targetNames.count) targets · \(active) active",
            "TRI pairs: \(snapshot.pairedPaths.count) · "
                + "misses: \(snapshot.associationMisses.count)",
            "Unknown target writes: \(snapshot.unknownTargetCount)"
        ]
        lines += snapshot.pairedPaths.prefix(3)
        lines += snapshot.associationMisses.prefix(3)
        statsLabel.stringValue = lines.joined(separator: "\n")
    }

    @objc private func targetChanged() {
        syncControls()
        finishInteraction()
    }

    @objc private func weightChanged() {
        guard let target = targetControl.titleOfSelectedItem else { return }
        provider?.setFaceMorphWeight(weightControl.floatValue, target: target)
        updateWeightLabel()
        finishInteraction(refocusOnMouseUpOnly: true)
    }

    @objc private func resetWeights() {
        provider?.resetFaceMorphWeights()
        syncControls()
        finishInteraction()
    }

    private func updateWeightLabel() {
        weightLabel.stringValue = String(format: "%4.2f", weightControl.floatValue)
    }
}
