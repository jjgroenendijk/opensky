// The launcher's view of a running world load: a progress bar, the stages
// that run now, one row per stage with its time, and a Cancel button.

import AppKit
import OpenSkyWorld

final class WorldLoadPanel: NSStackView {
    var onCancel: (() -> Void)?

    private let bar = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var rows: [WorldLoadStage: StageRow] = [:]

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = PanelMetrics.groupSpacing
        let heading = NSTextField(labelWithAttributedString: Theme.headingAttributed(
            "Loading world data",
            size: 13,
            color: Theme.parchment
        ))
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.setAccessibilityIdentifier("LauncherLoadProgressIndicator")
        bar.widthAnchor.constraint(equalToConstant: 440).isActive = true
        statusLabel.font = PanelMetrics.captionFont
        statusLabel.textColor = Theme.parchmentDim
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.widthAnchor.constraint(equalToConstant: 440).isActive = true
        statusLabel.setAccessibilityIdentifier("LauncherLoadStatusStatsLabel")
        PanelComponents.configureButton(
            cancelButton,
            target: self,
            action: #selector(cancel),
            identifier: "LauncherCancelLoadControl"
        )
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.toolTip = "Stop loading and stay in the launcher"
        for view in [heading, bar, statusLabel, makeStageGrid(), cancelButton] {
            addArrangedSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func show(_ timeline: WorldLoadTimeline, elapsed: Duration) {
        bar.doubleValue = timeline.fraction
        let running = timeline.runningStages.map(\.title).joined(separator: ", ")
        let total = WorldLoadStage.allCases.count
        statusLabel.stringValue = "\(timeline.finishedCount) of \(total) done, "
            + "\(elapsed.secondsText)" + (running.isEmpty ? "" : " — \(running)")
        for (stage, row) in rows {
            row.show(timeline.state(of: stage))
        }
    }

    /// Two columns, so all stages fit the launcher window without scrolling.
    private func makeStageGrid() -> NSView {
        let stages = WorldLoadStage.allCases
        let half = (stages.count + 1) / 2
        let columns = [stages[..<half], stages[half...]].map { column in
            let stack = NSStackView(views: column.map { stage in
                let row = StageRow(stage: stage)
                rows[stage] = row
                return row
            })
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 2
            return stack
        }
        let grid = NSStackView(views: columns)
        grid.alignment = .top
        grid.spacing = 24
        grid.setAccessibilityIdentifier("LauncherLoadStageList")
        return grid
    }

    @objc private func cancel() {
        onCancel?()
    }
}

/// One stage: a state symbol, the stage title, and its time once finished.
private final class StageRow: NSStackView {
    private let symbol = NSImageView()
    private let title: NSTextField
    private let time = NSTextField(labelWithString: "")

    init(stage: WorldLoadStage) {
        title = NSTextField(labelWithString: stage.title)
        super.init(frame: .zero)
        spacing = 6
        symbol.widthAnchor.constraint(equalToConstant: 14).isActive = true
        title.font = PanelMetrics.captionFont
        title.widthAnchor.constraint(equalToConstant: 150).isActive = true
        time.font = PanelMetrics.monoDigitFont
        time.alignment = .right
        time.widthAnchor.constraint(equalToConstant: 56).isActive = true
        for view in [symbol, title, time] {
            addArrangedSubview(view)
        }
        setAccessibilityIdentifier("LauncherLoadStage-\(stage.rawValue)")
        show(.pending)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func show(_ state: WorldLoadTimeline.StageState) {
        let text: String
        switch state {
        case .pending:
            setSymbol("circle", color: Theme.parchmentDim)
            text = ""
        case .running:
            setSymbol("hourglass", color: Theme.gold)
            text = "…"
        case let .finished(duration):
            setSymbol("checkmark.circle.fill", color: Theme.gold)
            text = duration.secondsText
        }
        title.textColor = state == .pending ? Theme.parchmentDim : Theme.parchment
        time.textColor = Theme.parchmentDim
        time.stringValue = text
        setAccessibilityValue(text.isEmpty ? "\(state)" : text)
    }

    private func setSymbol(_ name: String, color: NSColor) {
        symbol.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        symbol.contentTintColor = color
    }
}
