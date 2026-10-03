// World > Quests & Journal > Scenes: find a scene, start or stop it, and watch
// its phase, actions, and lines (docs/engine/scenes.md). Not overridden: a
// playing scene is world state, saved with the session.

import AppKit
import OpenSkyDialogue

final class ScenesSection: PanelSectionViewController {
    weak var provider: (any SceneControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    let sceneControl = NSComboBox()
    let startControl = NSButton(title: "Start", target: nil, action: nil)
    let stopControl = NSButton(title: "Stop", target: nil, action: nil)
    private var listedFilter: String?
    private let listLabel = PanelComponents.statsLabel(identifier: "ScenesListStatsLabel")
    private let statsLabel = PanelComponents.statsLabel(identifier: "ScenesStatsLabel")

    /// The readout text, for the panel tests.
    var readout: String {
        statsLabel.stringValue
    }

    var listReadout: String {
        listLabel.stringValue
    }

    override var sectionTitle: String {
        "Scenes"
    }

    override var sectionIdentifier: String {
        "scenes"
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureComboBox(
            sceneControl, target: self, action: #selector(sceneChanged),
            identifier: "ScenesSceneControl", width: 260
        )
        sceneControl.placeholderString = "scene editor ID"
        sceneControl.toolTip = "Type part of a scene name to list matches."
        startControl.toolTip = "Starts the scene. Its quest must be running."
        PanelComponents.configureButton(
            startControl, target: self, action: #selector(start), identifier: "ScenesStartControl"
        )
        PanelComponents.configureButton(
            stopControl, target: self, action: #selector(stop), identifier: "ScenesStopControl"
        )
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Scene",
                    captionWidth: 70,
                    field: sceneControl
                ),
                PanelComponents.buttonRow([startControl, stopControl])
            ]),
            listLabel,
            statsLabel
        ]
    }

    @objc private func sceneChanged() {
        refreshReadout()
    }

    @objc private func start() {
        provider?.startScene(editorID: sceneControl.stringValue)
        refreshReadout()
        finishInteraction()
    }

    @objc private func stop() {
        provider?.stopScene(editorID: sceneControl.stringValue)
        refreshReadout()
        finishInteraction()
    }

    override func refreshReadout() {
        guard let provider else {
            listLabel.stringValue = ""
            statsLabel.stringValue = "Scenes: unavailable"
            return
        }
        let filter = sceneControl.stringValue
        if filter != listedFilter {
            listedFilter = filter
            let rows = provider.sceneRows(matching: filter)
            sceneControl.removeAllItems()
            sceneControl.addItems(withObjectValues: rows.map(\.editorID))
            listLabel.stringValue = rows.map(Self.rowText).joined(separator: "\n")
        }
        statsLabel.stringValue = Self.statsText(provider.sceneSnapshot)
    }

    static func rowText(_ row: SceneListRow) -> String {
        "\(row.editorID): \(row.phaseCount) phases, \(row.actionCount) actions, "
            + "\(row.actorCount) actors\(row.isPlaying ? ", playing" : "")"
    }

    static func statsText(_ snapshot: SceneControlSnapshot) -> String {
        var lines = ["Scenes: \(snapshot.sceneCount)"]
        lines += snapshot.playing.isEmpty ? ["Playing: none"] : snapshot.playing.map { row in
            "Playing: \(row.editorID), phase \(row.phase) of \(row.phaseCount), "
                + "running \(row.runningActions.map(String.init).joined(separator: " "))"
        }
        lines.append("Last action: \(snapshot.lastOutcome ?? "none")")
        lines += ["Steps:"] + snapshot.trace
        lines += ["Lines:"] + (snapshot.lines.isEmpty ? ["none"] : snapshot.lines)
        return lines.joined(separator: "\n")
    }
}
