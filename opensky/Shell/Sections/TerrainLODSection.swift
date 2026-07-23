// World > Environment > Distant LOD section: editable per-level draw distances
// applied live, with an INI-reset + status line (issue #98 decomposition of the
// former Environment panel LOD controls).

import AppKit

final class TerrainLODSection: PanelSectionViewController {
    weak var provider: (any TerrainLODControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
        }
    }

    private let level0Field = NSTextField()
    private let level1Field = NSTextField()
    private let maximumField = NSTextField()
    private let treeField = NSTextField()
    private let statusLabel = PanelComponents.statsLabel(identifier: "LODStatusLabel")

    override var sectionTitle: String {
        "Distant LOD (world units)"
    }

    override var sectionIdentifier: String {
        "lod"
    }

    override func makeContentViews() -> [NSView] {
        configureField(level0Field, identifier: "LODLevel0DistanceField")
        configureField(level1Field, identifier: "LODLevel1DistanceField")
        configureField(maximumField, identifier: "LODMaximumDistanceField")
        configureField(treeField, identifier: "LODTreeDistanceField")

        let applyButton = NSButton(title: "Apply", target: self, action: #selector(apply))
        applyButton.setAccessibilityIdentifier("LODApplyButton")
        let resetButton = NSButton(
            title: "Use Skyrim INI", target: self, action: #selector(reset)
        )
        resetButton.setAccessibilityIdentifier("LODResetButton")

        return [
            row("L4 maximum", field: level0Field),
            row("L8 maximum", field: level1Field),
            row("Far maximum", field: maximumField),
            row("Trees", field: treeField),
            PanelComponents.buttonRow([resetButton, applyButton]),
            statusLabel
        ]
    }

    override func syncControls() {
        guard let snapshot = provider?.terrainLODConfigurationSnapshot else { return }
        let configuration = snapshot.configuration
        level0Field.stringValue = Self.distanceString(configuration.level0Distance)
        level1Field.stringValue = Self.distanceString(configuration.level1Distance)
        maximumField.stringValue = Self.distanceString(configuration.maximumDistance)
        treeField.stringValue = Self.distanceString(configuration.treeLoadDistance)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Source: \(snapshot.source). Apply rebuilds LOD live."
    }

    @objc private func apply() {
        guard
            let level0 = Float(level0Field.stringValue),
            let level1 = Float(level1Field.stringValue),
            let maximum = Float(maximumField.stringValue),
            let tree = Float(treeField.stringValue)
        else {
            showError("Enter numeric distances.")
            return
        }
        let configuration = TerrainLODConfiguration(
            level0Distance: level0,
            level1Distance: level1,
            maximumDistance: maximum,
            treeLoadDistance: tree
        )
        guard provider?.applyTerrainLODConfiguration(configuration) == true else {
            showError("Require 0 < L4 <= L8 <= Far; Trees > 0.")
            return
        }
        syncControls()
        refocusAction?()
    }

    @objc private func reset() {
        provider?.resetTerrainLODConfiguration()
        syncControls()
        refocusAction?()
    }

    private func showError(_ message: String) {
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = message
    }

    private func configureField(_ field: NSTextField, identifier: String) {
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        field.widthAnchor.constraint(equalToConstant: 105).isActive = true
        field.setAccessibilityIdentifier(identifier)
    }

    private func row(_ label: String, field: NSTextField) -> NSStackView {
        PanelComponents.labeledFieldRow(caption: label, captionWidth: 145, field: field)
    }

    private static func distanceString(_ value: Float) -> String {
        String(format: "%.0f", value)
    }
}
