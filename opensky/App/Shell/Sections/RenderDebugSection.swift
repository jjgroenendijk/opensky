// World > Render Debug section (issue #144): switch the scene pass's output
// channel, and switch layers off one at a time.
//
// The app's stated purpose is finding visual bugs, and until this section there
// was no way to bisect one — the only tools were reading code and staring at the
// frame. Two controls cover most of that gap: a debug channel says what a
// surface believes about itself, and a layer mask says which subsystem drew it.
//
// The solo popup deliberately writes the same mask the checkboxes do rather than
// carrying a stored "soloed layer" beside them: two stores for one state
// desynchronise, and a derived one cannot.
//
// Neither control persists. A session that starts in wireframe reads as a
// rendering bug, so both reset on launch and the sidebar's "Reset all" clears
// them the way it releases a frozen physics simulation.

import AppKit

final class RenderDebugSection: PanelSectionViewController {
    weak var provider: (any RenderDebugControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let modeControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let soloControl = NSPopUpButton(frame: .zero, pullsDown: false)
    /// One checkbox per layer, in `RenderLayer.ordered`.
    private(set) var layerControls: [NSButton] = []
    private let statsLabel = PanelComponents.statsLabel(identifier: "RenderDebugStatsLabel")
    private let modes = RenderDebugMode.allCases
    private let layers = RenderLayer.ordered
    /// First solo item: "no layer isolated", which is also what a mask holding
    /// several layers selects.
    private static let soloNoneTitle = "No isolation"

    override var sectionTitle: String {
        "Render Debug"
    }

    override var sectionIdentifier: String {
        "renderDebug"
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

    /// A debug channel or a hidden layer is by definition a non-default view of
    /// the frame, which is exactly what the sidebar dot is for.
    static func isOverridden(provider: (any RenderDebugControlProviding)?) -> Bool {
        guard let provider else { return false }
        return provider.renderDebugMode != .off || provider.renderDebugLayers != .all
    }

    static func resetToDefaults(provider: (any RenderDebugControlProviding)?) {
        provider?.renderDebugMode = .off
        provider?.renderDebugLayers = .all
    }

    override func makeContentViews() -> [NSView] {
        for mode in modes {
            modeControl.addItem(withTitle: mode.title)
        }
        PanelComponents.configurePopUp(
            modeControl, target: self, action: #selector(modeChanged),
            identifier: "RenderDebugModeControl"
        )
        soloControl.addItem(withTitle: Self.soloNoneTitle)
        for layer in layers {
            soloControl.addItem(withTitle: layer.title)
        }
        PanelComponents.configurePopUp(
            soloControl, target: self, action: #selector(soloChanged),
            identifier: "RenderDebugSoloControl"
        )
        layerControls = layers.map { layer in
            let checkbox = NSButton(checkboxWithTitle: layer.title, target: nil, action: nil)
            PanelComponents.configureCheckbox(
                checkbox, target: self, action: #selector(layerChanged),
                identifier: "RenderDebugLayer\(layer.identifierFragment)Control"
            )
            return checkbox
        }
        return [
            PanelComponents.note(
                "The view channel replaces the shaded surface for the whole scene: "
                    + "wireframe rasterises edges only, world normals, texture coordinates "
                    + "and mip level show what a surface believes about itself, shadow "
                    + "cascade colours which cascade shades it, and layer category colours "
                    + "which subsystem drew it. Layer isolation hides whole subsystems, "
                    + "shadow casting included, so a hidden layer leaves no shadow behind. "
                    + "Neither survives a relaunch, and neither reaches a screenshot or a "
                    + "bench run."
            ),
            PanelComponents.group([PanelComponents.caption("View channel"), modeControl]),
            PanelComponents.group(
                [PanelComponents.caption("Layers")] + layerControls
            ),
            PanelComponents.group([PanelComponents.caption("Isolate"), soloControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        modeControl.isEnabled = available
        soloControl.isEnabled = available
        for control in layerControls {
            control.isEnabled = available
        }
        guard let provider else { return }
        if let index = modes.firstIndex(of: provider.renderDebugMode) {
            modeControl.selectItem(at: index)
        }
        let mask = provider.renderDebugLayers
        for (control, layer) in zip(layerControls, layers) {
            control.state = mask.contains(layer) ? .on : .off
        }
        let soloed = mask.soloedLayer.flatMap { layers.firstIndex(of: $0) }
        soloControl.selectItem(at: soloed.map { $0 + 1 } ?? 0)
    }

    override func refreshReadout() {
        guard let snapshot = provider?.renderDebugSnapshot else {
            statsLabel.stringValue = "Render debug: unavailable"
            return
        }
        statsLabel.stringValue = RenderDebugReadout.text(for: snapshot)
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        let index = modeControl.indexOfSelectedItem
        guard modes.indices.contains(index) else { return }
        provider?.renderDebugMode = modes[index]
        finishInteraction()
    }

    /// Both layer controls write the same mask, so whichever one moved, the
    /// other has to be re-read from it. `finishInteraction` refreshes the
    /// readout and the override dot but deliberately not the controls, so the
    /// sync is explicit here — without it, isolating a layer would leave all
    /// eight checkboxes ticked while only one of them drew.
    private func applyLayers(_ mask: RenderLayer) {
        provider?.renderDebugLayers = mask
        syncControls()
        finishInteraction()
    }

    @objc private func layerChanged() {
        var mask = RenderLayer()
        for (control, layer) in zip(layerControls, layers) where control.state == .on {
            mask.insert(layer)
        }
        applyLayers(mask)
    }

    /// Item 0 restores every layer; the rest isolate one. Selecting the layer
    /// that is already soloed is a no-op rather than a toggle, because the popup
    /// shows a state and a state control should not flip out from under a
    /// deliberate re-selection.
    @objc private func soloChanged() {
        let index = soloControl.indexOfSelectedItem - 1
        applyLayers(layers.indices.contains(index) ? layers[index] : .all)
    }
}
