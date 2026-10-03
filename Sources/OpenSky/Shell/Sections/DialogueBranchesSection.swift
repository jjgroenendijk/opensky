// World > Dialogue & Voice > Dialogue Branches: how branches scoped the open
// conversation's topics, and a branch browser (docs/engine/dialogue.md).

import AppKit
import OpenSkyDialogue

final class DialogueBranchesSection: PanelSectionViewController {
    weak var provider: (any DialogueBranchControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    let filterControl = NSTextField()
    private var listedFilter: String?
    private let listLabel = PanelComponents.statsLabel(identifier: "DialogueBranchListStatsLabel")
    private let statsLabel = PanelComponents.statsLabel(identifier: "DialogueBranchStatsLabel")

    /// The readout text, for the panel tests.
    var readout: String {
        statsLabel.stringValue
    }

    var listReadout: String {
        listLabel.stringValue
    }

    override var sectionTitle: String {
        "Dialogue Branches"
    }

    override var sectionIdentifier: String {
        "dialogueBranches"
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureTextField(
            filterControl, identifier: "DialogueBranchFilterControl", width: 260,
            placeholder: "branch editor ID"
        )
        filterControl.toolTip = "Type part of a branch name to list matches."
        return [
            statsLabel,
            PanelComponents.labeledFieldRow(
                caption: "Branch",
                captionWidth: 70,
                field: filterControl
            ),
            listLabel
        ]
    }

    override func refreshReadout() {
        guard let provider else {
            listLabel.stringValue = ""
            statsLabel.stringValue = "Branches: unavailable"
            return
        }
        statsLabel.stringValue = Self.statsText(provider.dialogueBranchSnapshot)
        let filter = filterControl.stringValue
        guard filter != listedFilter else { return }
        listedFilter = filter
        listLabel.stringValue = provider.branchRows(matching: filter).joined(separator: "\n")
    }

    static func statsText(_ snapshot: DialogueBranchSnapshot) -> String {
        [
            "Branches: \(snapshot.branchCount), blocking \(snapshot.blockingCount)",
            "Offered topics: \(snapshot.offeredCount)",
            "Not a branch start: \(snapshot.notEntryCount)",
            "Blocked by branch: \(snapshot.blockedCount) (\(snapshot.blockingBranch ?? "none"))",
            "Exclusive branch: \(snapshot.exclusiveBranch ?? "none")"
        ].joined(separator: "\n")
    }
}
