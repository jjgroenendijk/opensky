// The launcher's Diagnostics page: what a problem report needs. It writes the
// logs to a folder and copies a system report with the newest benchmark result.

import AppKit
import Metal
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkyWorld

final class DiagnosticsPageViewController: NSViewController {
    let layout = LauncherPageLayout(pageName: "Diagnostics")
    let logsButton = LauncherButton(title: "Open Logs Folder", target: nil, action: nil)
    lazy var logsLabel = layout.line("DiagnosticsLogsStatsLabel")
    let copyButton = LauncherButton(title: "Copy System Report", target: nil, action: nil)
    let reportLabel = LauncherText(labelWithString: "")
    let benchmarkButton = LauncherButton(title: "Open Benchmark", target: nil, action: nil)
    lazy var benchmarkLabel = layout.line("DiagnosticsBenchmarkStatsLabel")
    private(set) var report = DiagnosticsPageViewController.currentReport()
    private var installCheck: Task<Void, Never>?
    private let context: LauncherContext

    init(context: LauncherContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    static func currentReport() -> SystemReport {
        let info = ProcessInfo.processInfo
        let bundle = Bundle.main.infoDictionary
        let version = (bundle?["CFBundleShortVersionString"] as? String ?? "development")
            + " (" + (bundle?["CFBundleVersion"] as? String ?? "0") + ")"
        let machine = BenchmarkMachine.current(gpu: MTLCreateSystemDefaultDevice()?.name ?? "none")
        return SystemReport(
            macOSVersion: info.operatingSystemVersionString, chip: machine.cpu, gpu: machine.gpu,
            memoryGB: machine.memoryGB, openSkyVersion: version
        )
    }

    override func loadView() {
        configureControls()
        view = layout.makeView(title: "Diagnostics", groups: [
            layout.group("Logs", [logsLabel, layout.buttons([logsButton])]),
            layout.group("System report", [reportLabel, layout.buttons([copyButton])]),
            layout.group("Benchmark", [benchmarkLabel, layout.buttons([benchmarkButton])])
        ])
        refreshReport()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshBenchmark()
        checkInstall()
    }

    /// The report carries the newest tour's frame time, so a problem report shows it.
    private func refreshBenchmark() {
        guard let frame = BenchmarkReport.latestRun()?.result.frameTime else {
            report.benchmark = nil
            benchmarkLabel.stringValue = "Benchmark: not run"
            refreshReport()
            return
        }
        let benchmark = SystemReportBenchmark(averageMS: frame.averageMS, worstMS: frame.worstMS)
        report.benchmark = benchmark
        benchmarkLabel.stringValue = "Benchmark: \(benchmark.line)"
        refreshReport()
    }

    private func configureControls() {
        let buttons = [
            (
                logsButton,
                #selector(openLogs),
                "DiagnosticsOpenLogsControl",
                "Write this run's log to a file"
            ),
            (
                copyButton,
                #selector(copyReport),
                "DiagnosticsCopyReportControl",
                "Copy the system report"
            ),
            (
                benchmarkButton,
                #selector(openBenchmark),
                "DiagnosticsBenchmarkControl",
                "Go to the Benchmark page to run the tour"
            )
        ]
        for (button, action, identifier, toolTip) in buttons {
            PanelComponents.configureButton(
                button,
                target: self,
                action: action,
                identifier: identifier
            )
            button.toolTip = toolTip
        }
        logsLabel.stringValue = "Logs: not written yet"
        reportLabel.font = PanelMetrics.monoFont
        reportLabel.textColor = LauncherStyle.textDim
        reportLabel.maximumNumberOfLines = 0
        reportLabel.isSelectable = true
        reportLabel.setAccessibilityIdentifier("DiagnosticsReportStatsLabel")
    }

    private func refreshReport() {
        reportLabel.stringValue = report.lines.joined(separator: "\n")
    }

    private func checkInstall() {
        let status = GameFolderStatus()
        guard let path = status.path else { return }
        installCheck?.cancel()
        installCheck = Task { [weak self] in
            let summary = await GameInstallCheck.check(installURL: URL(
                filePath: path,
                directoryHint: .isDirectory
            ))
            guard !Task.isCancelled else { return }
            self?.report.install = summary
            self?.refreshReport()
        }
    }

    @objc private func openLogs() {
        logsLabel.stringValue = "Logs: writing"
        Task { [weak self] in
            do {
                let url = try await SessionLogExport.export()
                self?.logsLabel.stringValue = "Logs: \(url.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                self?.logsLabel.stringValue = "Logs: not written, \(error.localizedDescription)"
            }
        }
    }

    @objc private func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.text, forType: .string)
    }

    @objc private func openBenchmark() {
        context.showPage("benchmark")
    }
}
