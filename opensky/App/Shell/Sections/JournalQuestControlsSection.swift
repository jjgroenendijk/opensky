// World > Quests & Journal > Quest Controls section (issue #184): the dev
// transport that makes the M13 loop drivable without a console.
//
// Start fills the quest's aliases and runs it, Stop clears them again, Set
// stage records one stage as reached, and the objective controls put a line on
// the journal page. Between them they reach every state the page can show, so
// the milestone can be walked end to end from the sidebar.
//
// Not overridden. A running quest is world state, not a panel setting; the
// destination's overridden-ness is the open journal, which the Page section
// owns, and stopping a quest the user deliberately started is not something a
// "Reset all" should do.

import AppKit

final class JournalQuestControlsSection: PanelSectionViewController {
    weak var provider: (any JournalControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let startControl = NSButton(title: "Start", target: nil, action: nil)
    let stopControl = NSButton(title: "Stop", target: nil, action: nil)
    let stageControl = NSTextField()
    let setStageControl = NSButton(title: "Set stage", target: nil, action: nil)
    let objectiveControl = NSTextField()
    let showObjectiveControl = NSButton(title: "Show", target: nil, action: nil)
    let hideObjectiveControl = NSButton(title: "Hide", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "JournalControlsStatsLabel"
    )

    override var sectionTitle: String {
        "Quest Controls"
    }

    override var sectionIdentifier: String {
        "journalQuestControls"
    }

    var readout: String {
        statsLabel.stringValue
    }

    /// Stage index typed into the field, or nil when it holds nothing usable.
    /// A non-numeric entry is nil rather than zero, because stage 0 is a legal
    /// stage and silently setting it would be a different action than the one
    /// asked for.
    var stageIndex: Int? {
        Int(stageControl.stringValue.trimmingCharacters(in: .whitespaces))
    }

    var objectiveIndex: Int? {
        Int(objectiveControl.stringValue.trimmingCharacters(in: .whitespaces))
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.note(
                "These act on the quest picked in the Quests section. Start fills the "
                    + "quest's aliases first and refuses the start if a non-optional one "
                    + "stays empty; Stop clears the table again. A stage the quest does not "
                    + "declare, and a stage set on a quest that is not running, are both "
                    + "refused rather than recorded."
            ),
            PanelComponents.buttonRow([startControl, stopControl]),
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Stage", captionWidth: 70, field: stageControl
                ),
                PanelComponents.buttonRow([setStageControl])
            ]),
            PanelComponents.group([
                PanelComponents.note(
                    "An objective appears on the page only while it is displayed, which is "
                        + "what the quest's own scripts would set."
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Objective", captionWidth: 70, field: objectiveControl
                ),
                PanelComponents.buttonRow([showObjectiveControl, hideObjectiveControl])
            ]),
            statsLabel
        ]
    }

    // MARK: Actions

    @objc private func start() {
        provider?.startSelectedQuest()
        refreshReadout()
        finishInteraction()
    }

    @objc private func stop() {
        provider?.stopSelectedQuest()
        refreshReadout()
        finishInteraction()
    }

    @objc private func setStage() {
        if let stageIndex {
            provider?.setSelectedQuestStage(stageIndex)
        }
        refreshReadout()
        finishInteraction()
    }

    @objc private func showObjective() {
        applyObjective(displayed: true)
    }

    @objc private func hideObjective() {
        applyObjective(displayed: false)
    }

    private func applyObjective(displayed: Bool) {
        if let objectiveIndex {
            provider?.setSelectedQuestObjective(objectiveIndex, displayed: displayed)
        }
        refreshReadout()
        finishInteraction()
    }

    // MARK: Sync and readout

    private func configureControls() {
        PanelComponents.configureButton(
            startControl, target: self, action: #selector(start),
            identifier: "JournalStartQuestControl"
        )
        PanelComponents.configureButton(
            stopControl, target: self, action: #selector(stop),
            identifier: "JournalStopQuestControl"
        )
        PanelComponents.configureTextField(
            stageControl, identifier: "JournalStageControl", width: 80, placeholder: "index"
        )
        PanelComponents.configureButton(
            setStageControl, target: self, action: #selector(setStage),
            identifier: "JournalSetStageControl"
        )
        PanelComponents.configureTextField(
            objectiveControl, identifier: "JournalObjectiveControl", width: 80,
            placeholder: "index"
        )
        PanelComponents.configureButton(
            showObjectiveControl, target: self, action: #selector(showObjective),
            identifier: "JournalShowObjectiveControl"
        )
        PanelComponents.configureButton(
            hideObjectiveControl, target: self, action: #selector(hideObjective),
            identifier: "JournalHideObjectiveControl"
        )
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Quests: unavailable"
            return
        }
        let snapshot = provider.journalSnapshot
        statsLabel.stringValue = snapshot.lastOutcome
            .map { "Last action: \($0)" }
            ?? "No quest change applied yet."
    }
}
