// World > Quests & Journal > Story Manager: browse an event's node tree, fire
// the event, and read the walk and the session-start pass
// (docs/engine/story-manager.md). Not overridden: a started quest is world state.

import AppKit
import OpenSkyFormatsESM
import OpenSkyQuests

final class StoryManagerSection: PanelSectionViewController {
    weak var provider: (any StoryManagerControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let eventControl = NSPopUpButton()
    let keywordControl = NSTextField()
    let valueControl = NSTextField()
    let fireControl = NSButton(title: "Fire", target: nil, action: nil)
    private let treeLabel = PanelComponents.statsLabel(identifier: "StoryTreeStatsLabel")
    private let statsLabel = PanelComponents.statsLabel(identifier: "StoryManagerStatsLabel")

    /// The readout text, for the panel tests.
    var readout: String {
        statsLabel.stringValue
    }

    var listReadout: String {
        treeLabel.stringValue
    }

    override var sectionTitle: String {
        "Story Manager"
    }

    override var sectionIdentifier: String {
        "storyManager"
    }

    /// The keyword FormID typed as hex, or nil when the field is empty or not hex.
    var keyword: FormID? {
        let text = keywordControl.stringValue.trimmingCharacters(in: .whitespaces)
        let digits = text.lowercased().hasPrefix("0x") ? String(text.dropFirst(2)) : text
        return UInt32(digits, radix: 16).map(FormID.init(stored:))
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configurePopUp(
            eventControl, target: self, action: #selector(eventChanged),
            identifier: "StoryEventControl", width: 120
        )
        PanelComponents.configureTextField(
            keywordControl, identifier: "StoryKeywordControl", width: 120, placeholder: "FormID"
        )
        PanelComponents.configureTextField(
            valueControl, identifier: "StoryValueControl", width: 80, placeholder: "0"
        )
        PanelComponents.configureButton(
            fireControl, target: self, action: #selector(fire), identifier: "StoryFireControl"
        )
        fireControl.toolTip = "Fires the event with the player as actor 1."
        syncControls()
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Event",
                    captionWidth: 70,
                    field: eventControl
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Keyword", captionWidth: 70, field: keywordControl
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Value 1",
                    captionWidth: 70,
                    field: valueControl
                ),
                PanelComponents.buttonRow([fireControl])
            ]),
            treeLabel,
            statsLabel
        ]
    }

    override func syncControls() {
        let codes = provider?.storyManagerSnapshot.events.map(\.code) ?? []
        guard eventControl.itemTitles != codes else { return }
        let selected = eventControl.titleOfSelectedItem
        eventControl.removeAllItems()
        eventControl.addItems(withTitles: codes)
        if let selected, codes.contains(selected) {
            eventControl.selectItem(withTitle: selected)
        }
    }

    @objc private func eventChanged() {
        refreshReadout()
    }

    @objc private func fire() {
        guard let code = eventControl.titleOfSelectedItem else { return }
        provider?.fireStoryEvent(code: code, keyword: keyword, value1: valueControl.floatValue)
        refreshReadout()
        finishInteraction()
    }

    override func refreshReadout() {
        guard let provider else {
            treeLabel.stringValue = ""
            statsLabel.stringValue = "Story manager: unavailable"
            return
        }
        let code = eventControl.titleOfSelectedItem ?? ""
        treeLabel.stringValue = (["Tree:"] + provider.storyTree(event: code))
            .joined(separator: "\n")
        statsLabel.stringValue = Self.statsText(provider.storyManagerSnapshot, event: code)
    }

    static func statsText(_ snapshot: StoryManagerSnapshot, event code: String) -> String {
        let row = snapshot.events.first { $0.code == code }
        var lines = [
            "Nodes: \(snapshot.nodeCount)",
            "Event nodes: \(row?.eventNodeCount ?? 0), fired \(row?.firedCount ?? 0)",
            "Session start: \(snapshot.sessionStart)",
            "Last walk: \(snapshot.lastOutcome ?? "none")"
        ]
        lines += snapshot.walkLines
        if snapshot.droppedWalkLines > 0 {
            lines.append("and \(snapshot.droppedWalkLines) more steps")
        }
        return lines.joined(separator: "\n")
    }
}
