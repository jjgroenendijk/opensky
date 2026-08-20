// World > Progression > Perk Tree section (issue #500, roadmap item 20.7): the
// selected skill's AVIF perk tree, box by box, and the resolved PERK record
// behind whichever box is selected.
//
// A list plus an inspector rather than a drawn grid. The tree's meaning is its
// connections, its rank chains and the rule that refuses a box, and every one
// of those reads as well spelled out as drawn — while a laid-out grid would be
// a second renderer to keep honest for no verification the list does not
// already give.
//
// Spend point is the real spend: it goes through the tree, the rank order and
// the perk's own conditions before it takes the point, and a refusal is printed
// as the rule that refused it. Grant and Remove are the dev way around all
// three, for reading what a perk does without qualifying for it first.
//
// The skill popup writes the same provider selection the Skills section above
// writes, so the two cannot describe different skills.
//
// Not overridden: an owned perk is world state, not a panel setting.

import AppKit

final class ProgressionPerkTreeSection: PanelSectionViewController {
    weak var provider: (any ProgressionControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

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

    var treeReadout: String {
        treeLabel.stringValue
    }

    var perkReadout: String {
        perkLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.note(
                "The tree is the selected skill's own AVIF perk grid: one row per box, "
                    + "with the perk it grants, how far along its rank chain the player "
                    + "has come, whether the box wants an owned parent, and the boxes it "
                    + "draws lines to. Each row also says whether a point can be spent on "
                    + "it right now, or which rule refuses it. Selecting a box shows that "
                    + "PERK record below — its flags, its own conditions, and every "
                    + "effect with the entry point, ability or quest stage it carries. "
                    + "Spend point takes a perk point and obeys every rule; Grant and "
                    + "Remove ignore the rules, for reading what a perk does."
            ),
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
        guard let provider else {
            treeLabel.stringValue = "Perk tree: unavailable"
            perkLabel.stringValue = "Selected perk: unavailable"
            return
        }
        let snapshot = provider.progressionControlSnapshot
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
        guard let snapshot = snapshot ?? provider?.progressionControlSnapshot else {
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
