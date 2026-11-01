// The launcher's Benchmark page: pick a tour length and where it shows, run it,
// and read the newest result. The same tour runs from `openskycli benchmark`.

import AppKit
import OpenSkyWorld

final class BenchmarkPageViewController: NSViewController {
    let layout = LauncherPageLayout()
    let presetControl = NSPopUpButton()
    let overlayControl = NSButton(checkboxWithTitle: "Show the overlay", target: nil, action: nil)
    let loadPassesControl = NSButton(
        checkboxWithTitle: "Time a cold and a warm load first", target: nil, action: nil
    )
    let screenshotsControl = NSButton(
        checkboxWithTitle: "Save screenshots", target: nil, action: nil
    )
    let displayControl = NSPopUpButton()
    let resolutionControl = NSPopUpButton()
    let soundControl = NSButton(checkboxWithTitle: "Play sound", target: nil, action: nil)
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
                layout.row("Display", displayControl),
                layout.row("Resolution", resolutionControl),
                layout.toggle(overlayControl), layout.toggle(loadPassesControl),
                layout.toggle(screenshotsControl), layout.toggle(soundControl),
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
        screenshotsControl.setAccessibilityIdentifier("BenchmarkScreenshotsControl")
        screenshotsControl.toolTip = "Save the start, middle, and end of each scene as PNGs"
        displayControl.addItems(withTitles: Self.displays.map(\.title))
        displayControl.toolTip = "Hidden draws off the screen, so you can keep working"
        resolutionControl.addItems(withTitles: Self.resolutions.map(Self.resolutionTitle))
        resolutionControl.setAccessibilityIdentifier("BenchmarkResolutionControl")
        resolutionControl.toolTip = "The frame size in pixels; full screen takes the display's"
        PanelComponents.configurePopUp(
            displayControl, target: self, action: #selector(displayChanged),
            identifier: "BenchmarkDisplayControl"
        )
        displayChanged()
        soundControl.setAccessibilityIdentifier("BenchmarkSoundControl")
        soundControl.toolTip = "Off keeps the tour silent; the audio update is measured either way"
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

    private static let displays: [BenchmarkDisplay] = [.fullScreen, .windowed, .hidden]

    var selectedDisplay: BenchmarkDisplay {
        let index = displayControl.indexOfSelectedItem
        return Self.displays.indices.contains(index) ? Self.displays[index] : .fullScreen
    }

    /// Nil keeps the window's size, or 1920x1080 for a hidden run.
    private static let resolutions: [BenchmarkFrameSize?] = [nil] + [
        (1280, 720), (1920, 1080), (2560, 1440), (3840, 2160)
    ].map { BenchmarkFrameSize(width: $0.0, height: $0.1) }

    private static func resolutionTitle(_ size: BenchmarkFrameSize?) -> String {
        size.map { "\($0.width) x \($0.height)" } ?? "Default"
    }

    var selectedResolution: BenchmarkFrameSize? {
        let index = resolutionControl.indexOfSelectedItem
        return Self.resolutions.indices.contains(index) ? Self.resolutions[index] : nil
    }

    @objc private func displayChanged() {
        resolutionControl.isEnabled = selectedDisplay != .fullScreen
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
        request.screenshots = screenshotsControl.state == .on
        request.display = selectedDisplay
        request.frameSize = selectedDisplay == .fullScreen ? nil : selectedResolution
        request.muted = soundControl.state != .on
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
