// The launcher's Asset Cache page: the preset, the folder and its limit, what
// the cache holds, and build, cancel, check, and clear. The logic lives in
// `AssetCacheCoordinator`; this page only shows it.

import AppKit
import OpenSkyAssetCache
import OpenSkyGameData
import OpenSkyWorld

final class AssetCachePageViewController: NSViewController {
    static let limitChoicesGiB = [0, 16, 32, 64, 128, 256]

    let coordinator: AssetCacheCoordinator
    let enabledCheckbox = NSButton(
        checkboxWithTitle: "Use the asset cache",
        target: nil,
        action: nil
    )
    let kindCheckboxes = AssetCacheKind.built.map { kind in
        NSButton(checkboxWithTitle: kind.title, target: nil, action: nil)
    }

    let retiredKindsLabel = NSTextField(labelWithString: AssetCacheReadout.retiredKindsNote)
    let presetPopUp = NSPopUpButton()
    let presetLabel = NSTextField(labelWithString: "")
    let folderLabel = NSTextField(labelWithString: "")
    let chooseFolderButton = NSButton(title: "Choose…", target: nil, action: nil)
    let defaultFolderButton = NSButton(title: "Use Default", target: nil, action: nil)
    let limitPopUp = NSPopUpButton()
    let sizeLabel = NSTextField(labelWithString: "")
    let stateLabel = NSTextField(labelWithString: "")
    let buildLabel = NSTextField(labelWithString: "")
    let problemLabel = NSTextField(labelWithString: "")
    let progressBar = NSProgressIndicator()
    let buildButton = NSButton(title: "Build", target: nil, action: nil)
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let checkButton = NSButton(title: "Check", target: nil, action: nil)
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
        let title = NSTextField(labelWithAttributedString: Theme.headingAttributed(
            "Asset Cache", size: 24, color: Theme.gold
        ))
        let stack = NSStackView(views: [
            title,
            PanelComponents.group([enabledCheckbox]),
            PanelComponents.group([PanelComponents.caption("Quality"), presetPopUp, presetLabel]),
            PanelComponents.group(
                [PanelComponents.caption("Stored in the cache")] + kindCheckboxes
                    + [retiredKindsLabel]
            ),
            PanelComponents.group([
                PanelComponents.caption("Folder"), folderLabel,
                PanelComponents.buttonRow([chooseFolderButton, defaultFolderButton]),
                PanelComponents.labeledFieldRow(
                    caption: "Size limit",
                    captionWidth: 80,
                    field: limitPopUp
                )
            ]),
            PanelComponents.group([sizeLabel, stateLabel, buildLabel, progressBar, problemLabel]),
            PanelComponents.buttonRow([buildButton, cancelButton, checkButton, clearButton])
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.edgeInsets = NSEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        view = stack
        coordinator.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        coordinator.reloadSettings(from: Self.savedSettings())
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if coordinator.check == nil, coordinator.activity == .idle {
            coordinator.startCheck()
        }
    }

    func refresh() {
        let settings = coordinator.settings
        let isIdle = coordinator.activity == .idle
        enabledCheckbox.state = settings.isEnabled ? .on : .off
        presetPopUp.selectItem(at: Int(settings.preset.rawValue))
        presetLabel.stringValue = settings.preset.values.summary
        for (kind, checkbox) in zip(AssetCacheKind.built, kindCheckboxes) {
            checkbox.state = settings.kinds.contains(kind) ? .on : .off
            checkbox.title = AssetCacheReadout.kindTitle(kind, usage: coordinator.usage)
            checkbox.isEnabled = isIdle
        }
        let folder = (try? settings.effectiveFolder())?.path(percentEncoded: false) ?? "None"
        folderLabel.stringValue = folder
        folderLabel.toolTip = folder
        limitPopUp
            .selectItem(at: Self.limitChoicesGiB
                .firstIndex(of: Int((settings.limitBytes ?? 0) >> 30)) ?? 0)
        limitPopUp.item(at: 0)?.title = "Default (\(settings.preset.defaultLimitBytes >> 30) GiB)"
        sizeLabel.stringValue = AssetCacheReadout.sizeLine(
            coordinator.usage,
            limitBytes: settings.effectiveLimitBytes
        )
        stateLabel.stringValue = AssetCacheReadout.stateLine(
            coordinator.check,
            activity: coordinator.activity
        )
        let building = coordinator.activity == .building
        buildLabel.stringValue = AssetCacheReadout.buildLine(
            coordinator.progress,
            isBuilding: building
        )
        progressBar.doubleValue = AssetCacheReadout.fraction(coordinator.progress)
        progressBar.isHidden = coordinator.progress == nil
        problemLabel.stringValue = coordinator.problem ?? ""
        problemLabel.isHidden = coordinator.problem == nil
        for control in [
            presetPopUp,
            chooseFolderButton,
            defaultFolderButton,
            limitPopUp
        ] as [NSControl] {
            control.isEnabled = isIdle
        }
        buildButton.isEnabled = isIdle
        checkButton.isEnabled = isIdle
        clearButton.isEnabled = isIdle
        cancelButton.isEnabled = building
    }
}
