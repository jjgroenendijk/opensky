// The launcher's Benchmark page: pick a tour length, run it in the Play window,
// and read the newest result. The same tour runs from `openskycli benchmark`.

import AppKit
import OpenSkyWorld

final class BenchmarkPageViewController: NSViewController {
    let layout = LauncherPageLayout(pageName: "Benchmark")
    let presetControl = NSPopUpButton()
    let overlayControl = NSButton(checkboxWithTitle: "Show the overlay", target: nil, action: nil)
    let loadPassesControl = NSButton(
        checkboxWithTitle: "Time a cold and a warm load first", target: nil, action: nil
    )
    let runButton = LauncherButton(title: "Run Benchmark", target: nil, action: nil)
    let folderButton = LauncherButton(title: "Open Run Folder", target: nil, action: nil)
    lazy var presetLabel = layout.line("BenchmarkPresetStatsLabel")
    lazy var resultLabel = layout.line("BenchmarkResultStatsLabel", mono: true)
    let chart = BenchmarkChartView()
    private let context: LauncherContext
    private var latestFolder: URL?

    init(context: LauncherContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        configureControls()
        view = layout.makeView(title: "Benchmark", groups: [
            layout.group("Run", [
                layout.row("Length", presetControl), presetLabel,
                layout.toggle(overlayControl), layout.toggle(loadPassesControl),
                layout.buttons([runButton])
            ]),
            layout.group("Newest result", [chart, resultLabel, layout.buttons([folderButton])])
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshResult()
    }

    private func configureControls() {
        presetControl.addItems(withTitles: BenchmarkPreset.allCases.map(\.title))
        presetControl.selectItem(at: BenchmarkPreset.allCases.firstIndex(of: .standard) ?? 0)
        PanelComponents.configurePopUp(
            presetControl, target: self, action: #selector(presetChanged),
            identifier: "BenchmarkPresetControl"
        )
        presetControl.toolTip = "Which scenes the tour visits"
        overlayControl.setAccessibilityIdentifier("BenchmarkOverlayControl")
        overlayControl.state = .on
        overlayControl.toolTip = "Show the scene and frame rate over the game; the toolbar hides it"
        loadPassesControl.setAccessibilityIdentifier("BenchmarkLoadPassesControl")
        loadPassesControl.state = .on
        loadPassesControl.toolTip = "Build the first scene twice off screen before the tour"
        PanelComponents.configureButton(
            runButton, target: self, action: #selector(run), identifier: "BenchmarkRunControl"
        )
        runButton.toolTip = "Open the Play window and fly the tour; the results show here"
        PanelComponents.configureButton(
            folderButton, target: self, action: #selector(openFolder),
            identifier: "BenchmarkOpenFolderControl"
        )
        folderButton.toolTip = "Show the run's result.json and summary.txt in Finder"
        resultLabel.maximumNumberOfLines = 0
        resultLabel.isSelectable = true
        chart.setAccessibilityIdentifier("BenchmarkChart")
        presetChanged()
    }

    private var selectedPreset: BenchmarkPreset {
        let index = presetControl.indexOfSelectedItem
        return BenchmarkPreset.allCases.indices.contains(index) ? BenchmarkPreset
            .allCases[index] : .standard
    }

    @objc private func presetChanged() {
        let preset = selectedPreset
        let count = preset.scenes().count
        presetLabel.stringValue = "Scenes: \(count), about \(count) min"
    }

    @objc private func run() {
        var request = BenchmarkRequest()
        request.preset = selectedPreset
        request.overlay = overlayControl.state == .on
        request.loadPasses = loadPassesControl.state == .on
        context.actions?.runBenchmark(request)
    }

    @objc private func openFolder() {
        guard let latestFolder else { return }
        NSWorkspace.shared
            .activateFileViewerSelecting([latestFolder.appending(path: BenchmarkReport.resultFile)])
    }

    func refreshResult() {
        let latest = BenchmarkReport.latestRun()
        latestFolder = latest?.folder
        folderButton.isEnabled = latest != nil
        chart.scenes = latest?.result.scenes ?? []
        resultLabel.stringValue = latest
            .map { BenchmarkReport.lines(for: $0.result).joined(separator: "\n") }
            ?? "Result: none yet"
    }
}
