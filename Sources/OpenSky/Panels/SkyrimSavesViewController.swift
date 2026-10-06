// Skyrim Saves: the `.ess` files in the saves folder setting, and a read-only
// inspection of the selected one. Nothing is imported here; Dry Run shows what an
// import would bring over. The logic lives in `ESSInspection` and `ESSImporter`.

import AppKit
import OpenSkyFormatsESS
import OpenSkyGameData
import OpenSkySave

final class SkyrimSavesViewController: NSViewController {
    var gameDataRoot: GameDataRoot?

    private(set) var listings: [ESSSaveListing] = []
    private var selectedFile: ESSFile?
    private var loadTask: Task<Void, Never>?

    let folderLabel = NSTextField(labelWithString: "")
    let tableView = NSTableView()
    let pictureView = NSImageView()
    let inspectionView = NSTextView()
    let chooseControl = NSButton()
    let reloadControl = NSButton()
    let dryRunControl = NSButton()

    override func loadView() {
        view = makeContentView()
        view.setAccessibilityIdentifier("SkyrimSaves")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reload()
    }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        let heading = NSTextField(labelWithString: "Skyrim Saves")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        folderLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.setAccessibilityIdentifier("SkyrimSavesFolderStatsLabel")
        configure(
            chooseControl,
            "Choose Folder…",
            "SkyrimSavesChooseControl",
            #selector(chooseFolder)
        )
        chooseControl.toolTip = "Pick the folder that holds your Skyrim .ess saves."
        configure(reloadControl, "Reload", "SkyrimSavesReloadControl", #selector(reloadFolder))
        configure(dryRunControl, "Dry Run Import", "SkyrimSavesDryRunControl", #selector(dryRun))
        dryRunControl.toolTip = "Run the import against the installed plugins without loading it."
        let buttons = NSStackView(views: [chooseControl, reloadControl, dryRunControl, NSView()])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        pictureView.imageScaling = .scaleProportionallyUpOrDown
        pictureView.setAccessibilityIdentifier("SkyrimSavesPictureView")
        pictureView.widthAnchor.constraint(equalToConstant: 192).isActive = true
        let detail = NSStackView(views: [makeTable(), pictureView])
        detail.orientation = .horizontal
        detail.alignment = .top
        let stack = NSStackView(views: [heading, folderLabel, buttons, detail, makeInspection()])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        return stack
    }

    private func configure(
        _ button: NSButton,
        _ title: String,
        _ identifier: String,
        _ action: Selector
    ) {
        button.bezelStyle = .rounded
        button.title = title
        button.target = self
        button.action = action
        button.setAccessibilityIdentifier(identifier)
    }

    private func makeTable() -> NSView {
        for (name, width) in [
            ("save", 220.0),
            ("character", 140.0),
            ("level", 50.0),
            ("place", 200.0)
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
            column.title = name.capitalized
            column.width = width
            tableView.addTableColumn(column)
        }
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityIdentifier("SkyrimSavesTable")
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        return scroll
    }

    private func makeInspection() -> NSView {
        inspectionView.isEditable = false
        inspectionView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        inspectionView.setAccessibilityIdentifier("SkyrimSavesInspectionText")
        let scroll = NSScrollView()
        scroll.documentView = inspectionView
        scroll.hasVerticalScroller = true
        inspectionView.autoresizingMask = [.width]
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        return scroll
    }

    // MARK: - State

    /// A listing reads only each file's header and picture.
    func reload() {
        guard isViewLoaded else { return }
        let folder = ESSSaveFolderSetting.folder()
        let status = ESSSaveFolder.status(of: folder)
        folderLabel.stringValue = status.message
        folderLabel.textColor = if case .ready = status {
            Theme.parchmentDim
        } else {
            .systemOrange
        }
        listings = (try? folder.map { try ESSSaveFolder(directory: $0).listings() }) ?? []
        tableView.reloadData()
        show(file: nil, text: listings.isEmpty ? "Save: none" : "Save: none selected")
    }

    private func show(file: ESSFile?, text: String) {
        selectedFile = file
        inspectionView.string = text
        dryRunControl.isEnabled = file != nil && gameDataRoot != nil
        let picture = file.flatMap { ESSSaveFolder.thumbnail(of: $0.screenshot) }
        pictureView.image = picture.flatMap(Self.image)
    }

    static func image(_ thumbnail: SaveThumbnail) -> NSImage? {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: thumbnail.width, pixelsHigh: thumbnail.height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: thumbnail.width * 4, bitsPerPixel: 32
        )
        guard let bitmap, let pixels = bitmap.bitmapData else { return nil }
        thumbnail.rgba.copyBytes(
            to: pixels,
            count: min(thumbnail.rgba.count, thumbnail.width * thumbnail.height * 4)
        )
        let image = NSImage(size: NSSize(width: thumbnail.width, height: thumbnail.height))
        image.addRepresentation(bitmap)
        return image
    }

    fileprivate func select(_ row: Int) {
        guard listings.indices.contains(row) else {
            show(file: nil, text: "Save: none selected")
            return
        }
        let url = listings[row].url
        let plugins = gameDataRoot
            .map { PluginLoadOrder.resolve(root: $0).entries.map(\.name) } ?? []
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            do {
                let file = try await ESSSaveFolder.readFile(at: url)
                guard !Task.isCancelled else { return }
                self?.show(
                    file: file,
                    text: ESSInspection(file: file, currentPlugins: plugins).text
                )
            } catch {
                self?.show(file: nil, text: "[ERROR] \(error)")
            }
        }
    }

    // MARK: - Actions

    @objc private func chooseFolder() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Select the folder holding your Skyrim .ess saves."
        panel.prompt = "Use Folder"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            ESSSaveFolderSetting.store(url)
            self?.reload()
        }
    }

    @objc private func reloadFolder() {
        reload()
    }

    /// Reads every plugin's headers off the main actor, so it can take seconds.
    @objc private func dryRun() {
        guard let file = selectedFile, let root = gameDataRoot else { return }
        dryRunControl.isEnabled = false
        inspectionView.string += "\n\n[INFO] dry run: reading the installed plugins"
        loadTask = Task { [weak self] in
            let index = await ESSPluginIndex.load(for: file, root: root)
            let records = ESSPluginRecords(index: index)
            let text = ESSInspection(file: file, currentPlugins: index.loadOrder, records: records)
                .text
            self?.show(file: file, text: text)
        }
    }
}

extension SkyrimSavesViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        listings.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn, listings.indices.contains(row) else { return nil }
        let listing = listings[row]
        let header = listing.summary?.header
        let text = switch tableColumn.identifier.rawValue {
        case "save": listing.name
        case "character": header?.playerName ?? (listing.error.map { "[ERROR] \($0)" } ?? "")
        case "level": header.map { "\($0.playerLevel)" } ?? ""
        default: header?.playerLocation ?? ""
        }
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        select(tableView.selectedRow)
    }
}

extension SkyrimSavesViewController: FullContentReloadable {
    func reloadFullContent(context: FullContentContext) {
        gameDataRoot = context.gameDataRoot
        reload()
    }
}
