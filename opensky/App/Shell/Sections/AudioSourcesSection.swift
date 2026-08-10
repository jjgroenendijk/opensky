// World > Audio > Sources section: the file picker + positional trigger and the
// live source list (position, distance, gain) — the M9.1.3 verification
// surface. The picker lists the install's `.xwm` files through the provider;
// playing places the source ahead of the camera so panning is audible at once.

import AppKit

final class AudioSourcesSection: PanelSectionViewController {
    weak var provider: (any AudioControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let fileControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let playControl = NSButton(title: "Play", target: nil, action: nil)
    let stopAllControl = NSButton(title: "Stop all", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "AudioSourcesStatsLabel")
    /// Last trigger failure, shown until the next trigger; nil after success.
    private var lastPlayError: String?

    override var sectionTitle: String {
        "Sources"
    }

    override var sectionIdentifier: String {
        "audioSources"
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configurePopUp(
            fileControl, target: self, action: #selector(fileChanged),
            identifier: "AudioFileControl", width: PanelMetrics.contentWidth
        )
        PanelComponents.configureButton(
            playControl, target: self, action: #selector(playSelected),
            identifier: "AudioPlaySelectedControl"
        )
        PanelComponents.configureButton(
            stopAllControl, target: self, action: #selector(stopAll),
            identifier: "AudioStopAllControl"
        )
        return [
            PanelComponents.group([
                fileControl,
                PanelComponents.buttonRow([playControl, stopAllControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let names = provider?.selectableAudioFileNames ?? []
        let selected = fileControl.titleOfSelectedItem
        fileControl.removeAllItems()
        fileControl.addItems(withTitles: names)
        if let selected, fileControl.itemTitles.contains(selected) {
            fileControl.selectItem(withTitle: selected)
        }
        fileControl.isEnabled = !names.isEmpty
        playControl.isEnabled = !names.isEmpty
        stopAllControl.isEnabled = provider != nil
    }

    @objc private func fileChanged() {
        finishInteraction()
    }

    @objc private func playSelected() {
        guard let name = fileControl.titleOfSelectedItem else { return }
        lastPlayError = provider?.playAudioFile(named: name)
        finishInteraction()
    }

    @objc private func stopAll() {
        provider?.stopAllAudioSources()
        finishInteraction()
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Sources: unavailable"
            return
        }
        let snapshot = provider.audioStatsSnapshot
        var lines = ["Sources: \(snapshot.sources.count) / \(snapshot.sourceCap)"]
        for source in snapshot.sources {
            let position = source.worldPosition
            // The clock reads nil until the source's player node has rendered
            // its first buffer, which is a real state and not a zero.
            let elapsed = source.positionSeconds
                .map { String(format: "%.2f s", $0) } ?? "--"
            lines.append(String(
                format: "%@ [%@] %.0f, %.0f, %.0f | %.1f m | gain %.2f | %@",
                Self.shortName(source.name), source.categoryName,
                position.x, position.y, position.z,
                source.distanceMeters, source.effectiveGain, elapsed
            ))
        }
        if let lastPlayError {
            lines.append("Play failed: \(lastPlayError)")
        }
        statsLabel.stringValue = lines.joined(separator: "\n")
    }

    /// Last path component, so a row fits the panel column.
    private static func shortName(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/").last.map(String.init) ?? path
    }
}
