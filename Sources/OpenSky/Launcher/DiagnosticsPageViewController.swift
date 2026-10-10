// The launcher's Diagnostics page: what a problem report needs. It writes the
// logs to a folder, copies a system report, and runs the shared benchmark.

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
    let benchmarkButton = LauncherButton(title: "Run Benchmark", target: nil, action: nil)
    lazy var benchmarkLabel = layout.line("DiagnosticsBenchmarkStatsLabel")
    private(set) var report = DiagnosticsPageViewController.currentReport()
    private var installCheck: Task<Void, Never>?

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
            layout.group("Benchmark", [
                benchmarkLabel, layout.buttons([benchmarkButton]),
                layout
                    .detail(layout
                        .note("The same run as openskycli benchmark, with the saved settings"))
            ])
        ])
        refreshReport()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        checkInstall()
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
                #selector(runBenchmark),
                "DiagnosticsBenchmarkControl",
                "Load and draw the fixed benchmark scene; takes about a minute"
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
        benchmarkLabel.stringValue = "Benchmark: not run"
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

    /// The benchmark renders on the main actor, so the page shows "Running" first.
    @objc private func runBenchmark() {
        guard
            let root = try? GameDataLocator.locate(),
            let device = MTLCreateSystemDefaultDevice()
        else {
            benchmarkLabel.stringValue = "Benchmark: no game folder or no GPU"
            return
        }
        benchmarkButton.isEnabled = false
        benchmarkLabel.stringValue = "Benchmark: running, the window waits until it ends"
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            let line: String
            do {
                let result = try StandardBenchmark.run(root: root, device: device)
                let frame = SystemReportBenchmark(
                    averageMS: result.frameTime.averageMS, worstMS: result.frameTime.worstMS
                )
                self?.report.benchmark = frame
                line = "Benchmark: \(frame.line)"
            } catch {
                line = "Benchmark: failed, \(error.localizedDescription)"
            }
            self?.benchmarkLabel.stringValue = line
            self?.benchmarkButton.isEnabled = true
            self?.refreshReport()
        }
    }
}
