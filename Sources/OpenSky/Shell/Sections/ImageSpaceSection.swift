// World > Effects > Image Space (docs/rendering/image-space.md): the
// post-process pass toggle, a forced baseline, and a modifier with a strength,
// above the live values the pass draws with.

import AppKit
import OpenSkyRendering
import OpenSkyWorld

final class ImageSpaceSection: PanelSectionViewController {
    weak var provider: (any ImageSpaceControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    static let followWeatherTitle = "Follow weather or cell"

    let passControl = NSButton(checkboxWithTitle: "Post-process pass", target: nil, action: nil)
    let toneMappingControl = NSButton(
        checkboxWithTitle: "HDR tone mapping", target: nil, action: nil
    )
    let forcedControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let modifierControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let strengthControl = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    let playControl = NSButton(title: "Play", target: nil, action: nil)
    let stopControl = NSButton(title: "Stop all", target: nil, action: nil)
    private let strengthLabel = PanelComponents.valueLabel(width: 48)
    private let statsLabel = PanelComponents.statsLabel(identifier: "ImageSpaceStatsLabel")
    private var forcedNames: [String] = []
    private var modifierNames: [String] = []

    override var sectionTitle: String {
        "Image Space"
    }

    override var sectionIdentifier: String {
        "imageSpace"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any ImageSpaceControlProviding)?) -> Bool {
        guard let provider else { return false }
        return !provider.imageSpacePassEnabled || provider.forcedImageSpaceName != nil
    }

    static func resetToDefaults(provider: (any ImageSpaceControlProviding)?) {
        provider?.imageSpacePassEnabled = true
        provider?.forcedImageSpaceName = nil
        provider?.stopImageSpaceModifiers()
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.group([
                passControl,
                toneMappingControl,
                PanelComponents.caption("Baseline"),
                forcedControl
            ]),
            PanelComponents.group([
                PanelComponents.caption("Modifier"),
                modifierControl,
                PanelComponents.sliderRow(slider: strengthControl, valueLabel: strengthLabel),
                PanelComponents.buttonRow([playControl, stopControl])
            ]),
            statsLabel
        ]
    }

    private func configureControls() {
        passControl.toolTip = "Off draws the frame without the image-space pass."
        PanelComponents.configureCheckbox(
            passControl, target: self, action: #selector(passChanged),
            identifier: "ImageSpacePassControl"
        )
        toneMappingControl.toolTip = "The eye adapts to the scene brightness, and the"
            + " image space white point maps to display white."
        PanelComponents.configureCheckbox(
            toneMappingControl, target: self, action: #selector(toneMappingChanged),
            identifier: "ImageSpaceToneMappingControl"
        )
        forcedControl.toolTip = "Forces one image space in place of the weather's."
        PanelComponents.configurePopUp(
            forcedControl, target: self, action: #selector(forcedChanged),
            identifier: "ImageSpaceForcedControl", width: PanelMetrics.contentWidth
        )
        PanelComponents.configurePopUp(
            modifierControl, target: self, action: #selector(modifierChanged),
            identifier: "ImageSpaceModifierControl", width: PanelMetrics.contentWidth
        )
        strengthControl.toolTip = "Strength of the next modifier you play."
        PanelComponents.configureSlider(
            strengthControl, target: self, action: #selector(strengthChanged),
            identifier: "ImageSpaceStrengthControl", width: PanelMetrics.contentWidth - 56
        )
        PanelComponents.configureButton(
            playControl, target: self, action: #selector(play), identifier: "ImageSpacePlayControl"
        )
        PanelComponents.configureButton(
            stopControl, target: self, action: #selector(stop), identifier: "ImageSpaceStopControl"
        )
    }

    override func syncControls() {
        let names = provider?.imageSpaceNames ?? []
        if names != forcedNames {
            forcedNames = names
            forcedControl.removeAllItems()
            forcedControl.addItems(withTitles: [Self.followWeatherTitle] + names)
        }
        let modifiers = provider?.imageSpaceModifierNames ?? []
        if modifiers != modifierNames {
            modifierNames = modifiers
            modifierControl.removeAllItems()
            modifierControl.addItems(withTitles: modifiers)
        }
        let forced = provider?.forcedImageSpaceName.flatMap { forcedNames.firstIndex(of: $0) }
        forcedControl.selectItem(at: forced.map { $0 + 1 } ?? 0)
        passControl.isEnabled = provider != nil
        passControl.state = provider?.imageSpacePassEnabled == false ? .off : .on
        toneMappingControl.isEnabled = provider != nil
        toneMappingControl.state = provider?.toneMappingEnabled == false ? .off : .on
        forcedControl.isEnabled = !forcedNames.isEmpty
        modifierControl.isEnabled = !modifierNames.isEmpty
        playControl.isEnabled = !modifierNames.isEmpty
        stopControl.isEnabled = provider != nil
        strengthLabel.stringValue = String(format: "%.2f", strengthControl.floatValue)
    }

    /// Syncs first: the record lists arrive with the session, after the panel opens.
    override func refreshReadout() {
        syncControls()
        guard let provider else {
            statsLabel.stringValue = "Image space: unavailable"
            return
        }
        statsLabel.stringValue = EffectsReadout.imageSpace(provider.imageSpaceState)
    }

    @objc private func passChanged() {
        provider?.imageSpacePassEnabled = passControl.state == .on
        finishInteraction()
    }

    @objc private func toneMappingChanged() {
        provider?.toneMappingEnabled = toneMappingControl.state == .on
        finishInteraction()
    }

    @objc private func forcedChanged() {
        let index = forcedControl.indexOfSelectedItem - 1
        provider?.forcedImageSpaceName = forcedNames.indices
            .contains(index) ? forcedNames[index] : nil
        finishInteraction()
    }

    @objc private func modifierChanged() {
        finishInteraction()
    }

    @objc private func strengthChanged() {
        syncControls()
        finishInteraction()
    }

    @objc private func play() {
        guard let name = modifierControl.titleOfSelectedItem else { return }
        provider?.startImageSpaceModifier(named: name, strength: strengthControl.floatValue)
        finishInteraction()
    }

    @objc private func stop() {
        provider?.stopImageSpaceModifiers()
        finishInteraction()
    }
}
