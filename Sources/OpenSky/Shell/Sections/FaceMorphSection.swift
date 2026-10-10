// World > HUD & Interaction > Face Morphs: pick a TRI target, scrub its 0...1
// weight, turn blinking and dialogue expressions on or off, and inspect association
// paths and misses.

import AppKit
import OpenSkyWorld

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
    let blinkControl = NSButton(checkboxWithTitle: "Blinking", target: nil, action: nil)
    let expressionControl = NSButton(
        checkboxWithTitle: "Dialogue expressions", target: nil, action: nil
    )
    let headTrackingControl = NSButton(
        checkboxWithTitle: "Head tracking", target: nil, action: nil
    )
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
        guard let provider else { return false }
        return provider.faceMorphSnapshot.weights.values.contains(where: { $0 != 0 })
            || !provider.automaticBlinkingEnabled || !provider.dialogueExpressionsEnabled
            || !provider.headTrackingEnabled
    }

    static func resetToDefaults(provider: (any FaceMorphControlProviding)?) {
        provider?.resetFaceMorphWeights()
        provider?.automaticBlinkingEnabled = true
        provider?.dialogueExpressionsEnabled = true
        provider?.headTrackingEnabled = true
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    override func makeContentViews() -> [NSView] {
        targetControl.toolTip = "The dialogue speaker, or else the crosshair target."
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
        PanelComponents.configureCheckbox(
            blinkControl, target: self, action: #selector(blinkChanged),
            identifier: "FaceMorphBlinkControl"
        )
        PanelComponents.configureCheckbox(
            expressionControl, target: self, action: #selector(expressionChanged),
            identifier: "FaceMorphExpressionControl"
        )
        expressionControl.toolTip = "A speaker shows the emotion of the line it says."
        PanelComponents.configureCheckbox(
            headTrackingControl, target: self, action: #selector(headTrackingChanged),
            identifier: "HeadTrackingControl"
        )
        headTrackingControl.toolTip = "Actors turn their heads toward what they look at."
        return [
            PanelComponents.group([
                targetControl,
                PanelComponents.sliderRow(slider: weightControl, valueLabel: weightLabel),
                resetControl
            ]),
            PanelComponents.group([blinkControl, expressionControl, headTrackingControl]),
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
        blinkControl.state = provider?.automaticBlinkingEnabled ?? true ? .on : .off
        expressionControl.state = provider?.dialogueExpressionsEnabled ?? true ? .on : .off
        headTrackingControl.state = provider?.headTrackingEnabled ?? true ? .on : .off
        headTrackingControl.isEnabled = provider != nil
        blinkControl.isEnabled = provider != nil
        expressionControl.isEnabled = provider != nil
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
            "Unknown target writes: \(snapshot.unknownTargetCount)",
            "Expression: " + Self.expressionText(snapshot.expressionWeights),
            "Head: " + (provider?.headTrackingReadout ?? "")
        ]
        lines += snapshot.pairedPaths.prefix(3)
        lines += snapshot.associationMisses.prefix(3)
        statsLabel.stringValue = lines.joined(separator: "\n")
    }

    static func expressionText(_ weights: [String: Float]) -> String {
        guard !weights.isEmpty else { return "none" }
        return weights.sorted { $0.key < $1.key }
            .map { "\($0.key) \(String(format: "%.2f", $0.value))" }
            .joined(separator: ", ")
    }

    @objc private func headTrackingChanged() {
        provider?.headTrackingEnabled = headTrackingControl.state == .on
        finishInteraction()
    }

    @objc private func blinkChanged() {
        provider?.automaticBlinkingEnabled = blinkControl.state == .on
        finishInteraction()
    }

    @objc private func expressionChanged() {
        provider?.dialogueExpressionsEnabled = expressionControl.state == .on
        finishInteraction()
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
