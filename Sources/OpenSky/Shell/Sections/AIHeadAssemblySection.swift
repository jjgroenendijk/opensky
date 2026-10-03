// World > AI & Navigation > Head Assembly: the head parts of the selected
// actor and the switch between its baked FaceGen head and the assembled one.
// The switch is world state on one actor, so Runtime State > Reset clears it.

import AppKit
import OpenSkyWorld

final class AIHeadAssemblySection: PanelSectionViewController {
    weak var provider: (any HeadAssemblyControlProviding)? {
        didSet { reloadIfLoaded() }
    }

    weak var selectionProvider: (any AINavigationControlProviding)? {
        didSet { reloadIfLoaded() }
    }

    let sourceControl = NSPopUpButton()
    private let statsLabel = PanelComponents.statsLabel(identifier: "HeadAssemblyStatsLabel")
    private static let sources: [ActorHeadSource] = [.baked, .assembled]

    override var sectionTitle: String {
        "Head Assembly"
    }

    override var sectionIdentifier: String {
        "aiHeadAssembly"
    }

    private var snapshot: HeadAssemblySnapshot? {
        provider?.headAssemblySnapshot(for: selectionProvider?.selectedAIActor)
    }

    override func makeContentViews() -> [NSView] {
        sourceControl.toolTip =
            "Baked uses the game's FaceGen head. Assembled loads each head part."
        sourceControl.addItems(
            withTitles: Self.sources.map { "Head: " + HeadAssemblyReadout.sourceText($0) }
        )
        PanelComponents.configurePopUp(
            sourceControl, target: self, action: #selector(sourceChanged),
            identifier: "HeadSourceControl", width: PanelMetrics.contentWidth
        )
        return [sourceControl, statsLabel]
    }

    override func syncControls() {
        let snapshot = snapshot
        sourceControl.isEnabled = snapshot?.actor != nil
        sourceControl
            .selectItem(at: Self.sources.firstIndex(of: snapshot?.requested ?? .baked) ?? 0)
    }

    override func refreshReadout() {
        guard let snapshot else {
            statsLabel.stringValue = "Head: unavailable"
            return
        }
        statsLabel.stringValue = HeadAssemblyReadout.text(for: snapshot)
    }

    private func reloadIfLoaded() {
        guard isViewLoaded else { return }
        syncControls()
        refreshReadout()
    }

    @objc private func sourceChanged() {
        let index = sourceControl.indexOfSelectedItem
        guard
            Self.sources.indices.contains(index),
            let actor = selectionProvider?.selectedAIActor
        else { return }
        provider?.setHeadSource(Self.sources[index], for: actor)
        refreshOverrideState()
        refreshReadout()
        finishInteraction()
    }
}
