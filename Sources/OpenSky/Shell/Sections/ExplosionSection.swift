// World > Effects > Explosions (docs/formats/explosions.md): detonate an
// explosion or throw debris in front of the camera, spawn a hazard there, and
// read the last blast and the live hazards.

import AppKit
import OpenSkyCombat

final class ExplosionSection: PanelSectionViewController {
    weak var provider: (any ExplosionControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let explosionControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let detonateControl = NSButton(title: "Detonate", target: nil, action: nil)
    let debrisControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let throwControl = NSButton(title: "Throw", target: nil, action: nil)
    let hazardControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let spawnControl = NSButton(title: "Spawn", target: nil, action: nil)
    let clearControl = NSButton(title: "Clear debris", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "ExplosionStatsLabel")
    private var lists: [[String]] = [[], [], []]
    private var lastAction: String?

    override var sectionTitle: String {
        "Explosions & Hazards"
    }

    override var sectionIdentifier: String {
        "explosions"
    }

    var readout: String {
        statsLabel.stringValue
    }

    private var popUps: [NSPopUpButton] {
        [explosionControl, debrisControl, hazardControl]
    }

    override func makeContentViews() -> [NSView] {
        let width = PanelMetrics.contentWidth - 110
        for (popUp, identifier) in zip(
            popUps,
            ["ExplosionSelectControl", "DebrisSelectControl", "HazardSelectControl"]
        ) {
            PanelComponents.configurePopUp(
                popUp, target: self, action: #selector(selectionChanged), identifier: identifier,
                width: width
            )
        }
        detonateControl.toolTip = "Sets off the explosion a short way in front of the camera."
        spawnControl.toolTip = "Places the hazard a short way in front of the camera."
        for (button, identifier) in [
            (detonateControl, "ExplosionDetonateControl"), (throwControl, "DebrisThrowControl"),
            (spawnControl, "HazardSpawnControl"), (clearControl, "ExplosionClearControl")
        ] {
            PanelComponents.configureButton(
                button, target: self, action: #selector(buttonPressed(_:)), identifier: identifier
            )
        }
        return [
            PanelComponents.group([
                row("Explosion", explosionControl, detonateControl),
                row("Debris", debrisControl, throwControl),
                row("Hazard", hazardControl, spawnControl),
                PanelComponents.buttonRow([clearControl])
            ]),
            statsLabel
        ]
    }

    private func row(_ caption: String, _ popUp: NSPopUpButton, _ button: NSButton) -> NSView {
        let row = PanelComponents.buttonRow([button])
        row.insertArrangedSubview(popUp, at: 0)
        return PanelComponents.group([PanelComponents.caption(caption), row])
    }

    override func syncControls() {
        let current = [
            provider?.explosionNames ?? [], provider?.debrisNames ?? [], provider?.hazardNames ?? []
        ]
        for (index, names) in current.enumerated() where names != lists[index] {
            lists[index] = names
            popUps[index].removeAllItems()
            popUps[index].addItems(withTitles: names)
        }
        for (popUp, button) in zip(popUps, [detonateControl, throwControl, spawnControl]) {
            popUp.isEnabled = popUp.numberOfItems > 0
            button.isEnabled = popUp.numberOfItems > 0
        }
        clearControl.isEnabled = provider != nil
    }

    override func refreshReadout() {
        syncControls()
        guard let provider else {
            statsLabel.stringValue = "Explosions: unavailable"
            return
        }
        let action = lastAction.map { "\nAction: \($0)" } ?? ""
        statsLabel.stringValue = ExplosionReadout.text(for: provider.explosionSnapshot) + action
    }

    @objc private func selectionChanged() {
        finishInteraction()
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        lastAction = perform(sender)
        refreshReadout()
        finishInteraction()
    }

    private func perform(_ sender: NSButton) -> String? {
        guard let provider else { return nil }
        switch sender {
        case detonateControl:
            guard let name = explosionControl.titleOfSelectedItem else { return nil }
            return provider.detonateExplosion(named: name) ? "\(name) detonated" : "\(name) failed"
        case throwControl:
            guard let name = debrisControl.titleOfSelectedItem else { return nil }
            return "\(provider.throwDebris(named: name)) pieces of \(name)"
        case spawnControl:
            guard let name = hazardControl.titleOfSelectedItem else { return nil }
            return provider.spawnHazard(named: name) ? "\(name) spawned" : "\(name) failed"
        default:
            provider.clearExplosions()
            return nil
        }
    }
}
