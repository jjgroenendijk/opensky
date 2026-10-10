// The launcher's Asset Optimisation page: the status of the optimised files, one
// Convert button, texture quality, direct GPU loading, and the folder with its
// space check. The logic lives in `AssetCacheCoordinator`; this page only shows it.

import AppKit
import OpenSkyAssetCache
import OpenSkyGameData
import OpenSkyWorld

final class AssetOptimisationPageViewController: NSViewController {
    let coordinator: AssetCacheCoordinator
    let layout = LauncherPageLayout(pageName: "AssetOptimisation")
    let status = LauncherStatusView(name: "AssetOptimisation")
    let convertButton = NSButton(title: "Convert", target: nil, action: nil)
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    lazy var convertReasonLabel = layout.line("AssetOptimisationConvertReasonStatsLabel")
    let progressBar = NSProgressIndicator()
    lazy var spaceLabel = layout.line("AssetOptimisationSpaceStatsLabel")
    lazy var spaceWarningLabel = layout.line("AssetOptimisationSpaceWarningStatsLabel")
    lazy var problemLabel = layout.line("AssetOptimisationProblemStatsLabel")
    let enabledCheckbox = NSButton(
        checkboxWithTitle: "Use optimised files",
        target: nil,
        action: nil
    )
    let qualityPopUp = NSPopUpButton()
    lazy var qualityChangeLabel = layout.line("AssetOptimisationTextureQualityStatsLabel")
    lazy var qualityLimitsLabel = layout.line(
        "AssetOptimisationQualityLimitsStatsLabel",
        mono: true
    )
    let formatPopUps = AssetTextureClass.allCases.map { _ in NSPopUpButton() }
    let directLoadCheckbox = NSButton(
        checkboxWithTitle: "Direct GPU loading",
        target: nil,
        action: nil
    )
    lazy var directLoadLabel = layout.line("AssetOptimisationDirectLoadStatsLabel")
    let directTexturesCheckbox = NSButton(checkboxWithTitle: "Textures", target: nil, action: nil)
    let directMeshesCheckbox = NSButton(checkboxWithTitle: "Meshes", target: nil, action: nil)
    let directAllDisksCheckbox = NSButton(
        checkboxWithTitle: "All disks, not only internal ones", target: nil, action: nil
    )
    lazy var folderLabel = layout.line("AssetOptimisationFolderStatsLabel", mono: true)
    lazy var sizeLabel = layout.line("AssetOptimisationSizeStatsLabel")
    let chooseFolderButton = NSButton(title: "Choose…", target: nil, action: nil)
    let defaultFolderButton = NSButton(title: "Use Default", target: nil, action: nil)
    let clearButton = NSButton(title: "Clear…", target: nil, action: nil)

    /// The settings file as saved now; the game window writes the same file.
    static func savedSettings() -> PlayerSettingsStore {
        PlayerSettingsStore(persistence: try? PlayerSettingsFile.defaultFile())
    }

    init(coordinator: AssetCacheCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        configureControls()
        view = layout.makeView(title: "Asset Optimisation", status: status, groups: [
            PanelComponents.group([
                PanelComponents.buttonRow([convertButton, cancelButton]), convertReasonLabel,
                progressBar, spaceLabel, spaceWarningLabel, problemLabel
            ]),
            layout.group("Optimised files", [enabledCheckbox]),
            layout.group("Textures", [
                PanelComponents.labeledFieldRow(
                    caption: "Quality",
                    captionWidth: 80,
                    field: qualityPopUp
                ),
                qualityChangeLabel, layout.detail(qualityLimitsLabel)
            ] + formatRows()),
            layout.group(
                "Meshes and collision",
                [layout.note(AssetOptimisationReadout.meshesLine)]
            ),
            layout.detail(layout.group(
                "Converted from and to", AssetOptimisationReadout.conversionLines.map(layout.note)
            )),
            layout.group("Direct GPU loading", [
                directLoadCheckbox, directLoadLabel,
                layout.note(AssetOptimisationReadout.directLoadReason),
                layout.detail(PanelComponents.group([
                    directTexturesCheckbox, directMeshesCheckbox, directAllDisksCheckbox
                ]))
            ]),
            layout.group("Folder", [
                folderLabel, sizeLabel,
                PanelComponents.buttonRow([chooseFolderButton, defaultFolderButton, clearButton])
            ])
        ])
        coordinator.onChange = { [weak self] in self?.refresh() }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        coordinator.reloadSettings(from: Self.savedSettings())
    }

    /// The page checks on its own, so it has no Check button.
    override func viewDidAppear() {
        super.viewDidAppear()
        if coordinator.check == nil, coordinator.activity == .idle {
            coordinator.startCheck()
        }
    }

    private func formatRows() -> [NSView] {
        zip(AssetTextureClass.allCases, formatPopUps).map { group, popUp in
            layout.detail(PanelComponents.labeledFieldRow(
                caption: group.title, captionWidth: 80, field: popUp
            ))
        }
    }

    func refresh() {
        let settings = coordinator.settings
        let isIdle = coordinator.activity == .idle
        let state = coordinator.status
        status.show(
            symbol: state.symbolName, title: state.title, detail: state.detail,
            colour: state == .ready ? .systemGreen : state.needsConversion ? .systemOrange : Theme
                .parchmentDim
        )
        let reason = coordinator.convertDisabledReason
        convertButton.isEnabled = reason == nil
        convertReasonLabel.stringValue = reason ?? ""
        convertReasonLabel.isHidden = reason == nil
        cancelButton.isEnabled = coordinator.activity == .building
        progressBar.doubleValue = AssetCacheReadout.fraction(coordinator.progress)
        progressBar.isHidden = coordinator.activity != .building
        let space = coordinator.spaceCheck
        spaceLabel.stringValue = space?.line ?? "Space: checking"
        let warning = space?.warnings.map(\.message).joined(separator: " ") ?? ""
        spaceWarningLabel.stringValue = warning
        spaceWarningLabel.toolTip = warning
        spaceWarningLabel.isHidden = warning.isEmpty
        problemLabel.stringValue = coordinator.problem ?? ""
        problemLabel.isHidden = coordinator.problem == nil
        enabledCheckbox.state = settings.isEnabled ? .on : .off
        refreshTextures(settings)
        refreshDirectLoad(settings, state: state)
        let folder = (try? settings.effectiveFolder())?.path(percentEncoded: false) ?? "None"
        folderLabel.stringValue = folder
        folderLabel.toolTip = folder
        sizeLabel.stringValue = AssetCacheReadout.sizeLine(coordinator.usage)
        for control in [qualityPopUp, chooseFolderButton, defaultFolderButton, clearButton] +
            formatPopUps
            as [NSControl]
        {
            control.isEnabled = isIdle
        }
    }

    private func refreshTextures(_ settings: AssetCacheSettings) {
        let output = settings.textureOutput
        qualityPopUp.selectItem(at: Int(output.quality.rawValue))
        let change = AssetOptimisationReadout.textureChangeLine(coordinator.check, output: output)
        qualityChangeLabel.stringValue = change ?? output.quality.label
        qualityLimitsLabel.stringValue = AssetOptimisationReadout.qualityLimitLine(output.quality)
        for (group, popUp) in zip(AssetTextureClass.allCases, formatPopUps) {
            popUp.selectItem(at: Int((output.formats[group] ?? .automatic).rawValue))
        }
    }

    private func refreshDirectLoad(_ settings: AssetCacheSettings, state: AssetOptimisationStatus) {
        let load = settings.directLoad
        directLoadCheckbox.state = load.isEnabled ? .on : .off
        directTexturesCheckbox.state = load.textures ? .on : .off
        directMeshesCheckbox.state = load.meshes ? .on : .off
        directAllDisksCheckbox.state = load.allDisks ? .on : .off
        for checkbox in [directTexturesCheckbox, directMeshesCheckbox, directAllDisksCheckbox] {
            checkbox.isEnabled = load.isEnabled
        }
        directLoadLabel.stringValue = AssetOptimisationReadout.directLoadStatus(
            settings, volume: coordinator.volume, status: state
        )
    }
}
