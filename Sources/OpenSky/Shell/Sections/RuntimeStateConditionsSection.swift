// World > Runtime State > Conditions section: evaluates one decoded CTDA list
// against the live world and reports the verdict, each condition's reason, and
// the session's `ConditionTally`. The per-condition reasons tell "not
// implemented" apart from "not satisfied". Never overridden.

import AppKit
import OpenSkyWorld

final class RuntimeStateConditionsSection: PanelSectionViewController {
    weak var provider: (any RuntimeStateControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let conditionSourceControl = NSComboBox()
    let conditionEvaluateControl = NSButton(title: "Evaluate", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "RuntimeStateConditionStatsLabel"
    )
    private let tallyLabel = PanelComponents.statsLabel(
        identifier: "RuntimeStateConditionTallyStatsLabel"
    )
    private var report = RuntimeStateConditionReport.empty
    /// Source list the combo box currently holds; rebuilt only when it changes,
    /// because the readout ticker calls `syncControls` on every panel reveal.
    private var loadedSources: [String] = []

    override var sectionTitle: String {
        "Conditions"
    }

    override var sectionIdentifier: String {
        "runtimeStateConditions"
    }

    /// The condition list the Evaluate button acts on.
    var conditionSource: String {
        conditionSourceControl.stringValue.trimmingCharacters(in: .whitespaces)
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureComboBox(
            conditionSourceControl, target: self, action: #selector(sourceSelected),
            identifier: "RuntimeStateConditionSourceControl", width: 200
        )
        PanelComponents.configureButton(
            conditionEvaluateControl, target: self, action: #selector(evaluate),
            identifier: "RuntimeStateConditionEvaluateControl"
        )
        return [
            PanelComponents.group([
                PanelComponents.note(
                    "Condition lists come from the music tracks that author CTDA conditions, "
                        + "the engine's decoded carrier for them. Evaluation runs against the "
                        + "live globals, the live clock, and the reference the crosshair is on."
                ),
                conditionSourceControl
            ]),
            PanelComponents.buttonRow([conditionEvaluateControl]),
            statsLabel,
            PanelComponents.caption("Tally (this session)"),
            tallyLabel
        ]
    }

    // MARK: Actions

    @objc private func sourceSelected() {
        finishInteraction()
    }

    @objc private func evaluate() {
        guard let provider, !conditionSource.isEmpty else {
            report = .unavailable(
                source: conditionSource, message: "Pick a condition list first."
            )
            finishInteraction()
            return
        }
        report = provider.evaluateConditions(source: conditionSource)
        finishInteraction()
    }

    // MARK: Sync and readout

    override func syncControls() {
        let available = provider?.runtimeStateConditionSources ?? []
        guard available != loadedSources else { return }
        loadedSources = available
        conditionSourceControl.removeAllItems()
        conditionSourceControl.addItems(withObjectValues: available)
    }

    override func refreshReadout() {
        guard provider != nil else {
            statsLabel.stringValue = "Runtime state: unavailable"
            tallyLabel.stringValue = ""
            return
        }
        statsLabel.stringValue = Self.reportText(report)
        tallyLabel.stringValue = report.tallyLines.isEmpty
            ? "Nothing evaluated yet."
            : report.tallyLines.joined(separator: "\n")
    }

    /// Verdict first, then one line per condition. A report carrying a message
    /// shows only that message: there is no verdict to state.
    nonisolated static func reportText(_ report: RuntimeStateConditionReport) -> String {
        if let message = report.message {
            return message
        }
        var lines = [
            "\(report.source): \(report.isSatisfied ? "satisfied" : "not satisfied")"
                + " (\(report.lines.count) conditions)"
        ]
        lines.append(contentsOf: report.lines.map(Self.lineText))
        return lines.joined(separator: "\n")
    }

    nonisolated static func lineText(_ line: RuntimeStateConditionLine) -> String {
        "\(line.index). \(line.text) -> \(line.isTrue) [\(line.reason)]"
    }
}
