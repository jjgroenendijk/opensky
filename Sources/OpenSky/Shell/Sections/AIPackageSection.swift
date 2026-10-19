// World > AI & Navigation > Package section: which package the selected
// actor's schedule chose, its running procedures, a force-reevaluate button, and
// the script package that AddScriptPackage gives. The schedule and conditions pick
// every other package: scrub the clock under World > Runtime State > Time, then reevaluate.

import AppKit
import OpenSkyAIPackages

final class AIPackageSection: PanelSectionViewController {
    weak var provider: (any AINavigationControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let reevaluateControl = NSButton(title: "Reevaluate now", target: nil, action: nil)
    let scriptPackageControl = NSTextField(string: "")
    let addScriptPackageControl = NSButton(title: "Add script package", target: nil, action: nil)
    let removeScriptPackageControl = NSButton(title: "Remove", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "AIPackageStatsLabel")

    override var sectionTitle: String {
        "Package"
    }

    override var sectionIdentifier: String {
        "aiPackage"
    }

    override func makeContentViews() -> [NSView] {
        reevaluateControl.toolTip =
            "Picks the package again now and starts its procedures from the beginning. "
                + "Change the clock under Runtime State > Time first."
        PanelComponents.configureButton(
            reevaluateControl, target: self, action: #selector(reevaluate),
            identifier: "AIPackageReevaluateControl"
        )
        scriptPackageControl.toolTip = "A package editor ID or FormID, as AddScriptPackage takes."
        addScriptPackageControl.toolTip = "The package runs ahead of all others until it is done."
        removeScriptPackageControl.toolTip = "Removes it, as RemoveScriptPackage does."
        PanelComponents.configureTextField(
            scriptPackageControl, identifier: "AIScriptPackageControl",
            width: PanelMetrics.contentWidth
        )
        PanelComponents.configureButton(
            addScriptPackageControl, target: self, action: #selector(addScriptPackage),
            identifier: "AIAddScriptPackageControl"
        )
        PanelComponents.configureButton(
            removeScriptPackageControl, target: self, action: #selector(removeScriptPackage),
            identifier: "AIRemoveScriptPackageControl"
        )
        return [
            PanelComponents.buttonRow([reevaluateControl]),
            PanelComponents.group([
                scriptPackageControl,
                PanelComponents.buttonRow([addScriptPackageControl, removeScriptPackageControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        for control in [reevaluateControl, addScriptPackageControl, removeScriptPackageControl] {
            control.isEnabled = provider != nil
        }
    }

    override func refreshReadout() {
        guard let snapshot = provider?.aiNavigationSnapshot else {
            statsLabel.stringValue = "Package: unavailable"
            return
        }
        statsLabel.stringValue = AIPackageReadout.packageText(for: snapshot)
    }

    // MARK: - Actions

    @objc private func reevaluate() {
        provider?.reevaluateSelectedAIActorPackage()
        finishInteraction()
    }

    @objc private func addScriptPackage() {
        let name = scriptPackageControl.stringValue.trimmingCharacters(in: .whitespaces)
        provider?.setSelectedAIActorScriptPackage(name.isEmpty ? nil : name)
        refreshReadout()
        finishInteraction()
    }

    @objc private func removeScriptPackage() {
        provider?.setSelectedAIActorScriptPackage(nil)
        refreshReadout()
        finishInteraction()
    }
}
