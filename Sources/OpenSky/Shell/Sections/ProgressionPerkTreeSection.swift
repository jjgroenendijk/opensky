// World > Progression > Perk Tree section: the selected skill's AVIF perk tree
// as a list, plus the PERK record behind the selected box. Spend point checks
// the tree, rank order, and conditions and prints any refusal; Grant and Remove
// bypass them. The skill popup shares the provider selection with the Skills
// section. Not overridden.

import AppKit
import OpenSkyProgression

final class ProgressionPerkTreeSection: ProgressionPanelSection {
    let skillControl = NSPopUpButton()
    let nodeControl = NSPopUpButton()
    let spendControl = NSButton(title: "Spend point", target: nil, action: nil)
    let grantControl = NSButton(title: "Grant", target: nil, action: nil)
    let removeControl = NSButton(title: "Remove", target: nil, action: nil)

    private let treeLabel = PanelComponents.statsLabel(
        identifier: "ProgressionPerkTreeStatsLabel"
    )
    private let perkLabel = PanelComponents.statsLabel(
        identifier: "ProgressionPerkStatsLabel"
    )
    private var skillOptions: [SkillProgressReadout] = []
    private var nodeOptions: [PerkTreeNodeReadout] = []

    override var sectionTitle: String {
        "Perk Tree"
    }

    override var sectionIdentifier: String {
        "progressionPerkTree"
    }

    override func makeContentViews() -> [NSView] {
        spendControl.toolTip = "Spends a perk point. Follows every rule."
        grantControl.toolTip = "Gives the perk. Ignores the rules."
        removeControl.toolTip = "Removes the perk. Ignores the rules."
        configureControls()
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Skill", captionWidth: 70, field: skillControl
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Box", captionWidth: 70, field: nodeControl
                ),
                PanelComponents.buttonRow([spendControl, grantControl, removeControl])
            ]),
            treeLabel,
            perkLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        for control in [spendControl, grantControl, removeControl] {
            control.isEnabled = available
        }
        skillControl.isEnabled = available
        nodeControl.isEnabled = available
        reloadOptions()
    }

    override func refreshReadout() {
        guard let snapshot = currentSnapshot else {
            treeLabel.stringValue = "Perk tree: unavailable"
            perkLabel.stringValue = "Selected perk: unavailable"
            return
        }
        reloadOptions(snapshot: snapshot)
        treeLabel.stringValue = ProgressionControlReadout.perkTreeText(for: snapshot)
        perkLabel.stringValue = ProgressionControlReadout.perkText(for: snapshot)
    }

    /// A box's popup row: its `INAM` and the perk it grants, which is what the
    /// tree readout addresses it by. Nothing that moves twice a second, so the
    /// list is rebuilt only when the tree itself changes.
    nonisolated static func title(for node: PerkTreeNodeReadout) -> String {
        "#\(node.node) \(node.name)"
    }

    // MARK: - Wiring

    private func configureControls() {
        PanelComponents.configurePopUp(
            skillControl, target: self, action: #selector(skillChanged),
            identifier: "ProgressionTreeSkillControl", width: 160
        )
        PanelComponents.configurePopUp(
            nodeControl, target: self, action: #selector(nodeChanged),
            identifier: "ProgressionPerkNodeControl", width: 160
        )
        PanelComponents.configureButton(
            spendControl, target: self, action: #selector(spendPoint),
            identifier: "ProgressionSpendPerkPointControl"
        )
        PanelComponents.configureButton(
            grantControl, target: self, action: #selector(grant),
            identifier: "ProgressionGrantPerkControl"
        )
        PanelComponents.configureButton(
            removeControl, target: self, action: #selector(remove),
            identifier: "ProgressionRemovePerkControl"
        )
    }

    private func reloadOptions(snapshot: ProgressionControlSnapshot? = nil) {
        guard let snapshot = snapshot ?? currentSnapshot else {
            skillOptions = []
            nodeOptions = []
            skillControl.removeAllItems()
            nodeControl.removeAllItems()
            return
        }
        reloadSkills(snapshot)
        reloadNodes(snapshot)
    }

    private func reloadSkills(_ snapshot: ProgressionControlSnapshot) {
        skillControl.isEnabled = !snapshot.skills.isEmpty
        if snapshot.skills.map(\.name) != skillOptions.map(\.name) {
            skillOptions = snapshot.skills
            skillControl.removeAllItems()
            skillControl.addItems(withTitles: skillOptions.map(\.name))
        } else {
            skillOptions = snapshot.skills
        }
        guard
            let index = skillOptions.firstIndex(where: {
                $0.index == snapshot.selectedSkill
            })
        else { return }
        skillControl.selectItem(at: index)
    }

    private func reloadNodes(_ snapshot: ProgressionControlSnapshot) {
        nodeControl.isEnabled = !snapshot.treeNodes.isEmpty
        let titles = snapshot.treeNodes.map(Self.title(for:))
        if titles != nodeOptions.map(Self.title(for:)) {
            nodeOptions = snapshot.treeNodes
            nodeControl.removeAllItems()
            nodeControl.addItems(withTitles: titles)
        } else {
            nodeOptions = snapshot.treeNodes
        }
        guard
            let index = nodeOptions.firstIndex(where: { $0.node == snapshot.selectedNode })
        else { return }
        nodeControl.selectItem(at: index)
    }

    // MARK: - Actions

    @objc private func skillChanged() {
        let index = skillControl.indexOfSelectedItem
        guard skillOptions.indices.contains(index) else { return }
        provider?.progressionSkillSelection = skillOptions[index].index
        finishInteraction()
    }

    @objc private func nodeChanged() {
        let index = nodeControl.indexOfSelectedItem
        guard nodeOptions.indices.contains(index) else { return }
        provider?.progressionNodeSelection = nodeOptions[index].node
        finishInteraction()
    }

    @objc private func spendPoint() {
        provider?.spendPointOnSelectedPerk()
        finishInteraction()
    }

    @objc private func grant() {
        provider?.grantSelectedPerk()
        finishInteraction()
    }

    @objc private func remove() {
        provider?.revokeSelectedPerk()
        finishInteraction()
    }
}
