// VFS + record browser (todo 2.10): sidebar with category selector, filter
// field and a lazy table over the catalog rows; detail pane with preview
// image + info text. The catalog loads off the main thread (opening every
// archive and walking Skyrim.esm takes seconds); filtering the ~870k record
// rows runs off-main too, latest generation wins. Browse logic lives in
// opensky/Preview/ (AppKit-free, unit-tested); this file is the UI shell.

import AppKit

final class PreviewViewController: NSViewController {
    /// Located install, set by the app delegate before the view loads;
    /// nil -> `startupErrorMessage` explains why.
    var gameDataRoot: GameDataRoot?
    /// Locator failure text shown in-window (the app still launches).
    var startupErrorMessage: String?

    private var catalog: PreviewCatalog?
    private var detailBuilder: PreviewDetailBuilder?
    private var visibleItems: [PreviewItem] = []
    /// Bumped per filter request; stale off-main results are dropped.
    private var filterGeneration = 0

    private let categoryPopUp = NSPopUpButton()
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    private let infoScroll = NSTextView.scrollableTextView()

    private var infoTextView: NSTextView? {
        infoScroll.documentView as? NSTextView
    }

    private var selectedCategory: PreviewCategory {
        let all = PreviewCategory.allCases
        let index = categoryPopUp.indexOfSelectedItem
        return all.indices.contains(index) ? all[index] : .meshes
    }

    // MARK: - Lifecycle

    override func loadView() {
        let split = NSSplitView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        split.isVertical = true
        split.dividerStyle = .thin
        let sidebar = makeSidebar()
        let detail = makeDetailPane()
        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(detail)
        sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 340).isActive = true
        detail.widthAnchor.constraint(greaterThanOrEqualToConstant: 480).isActive = true
        split.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
        view = split
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let root = gameDataRoot else {
            statusLabel.stringValue = startupErrorMessage ?? "Game data not located."
            infoTextView?.string = startupErrorMessage ?? ""
            return
        }
        loadCatalog(root: root)
    }

    // MARK: - Layout

    private func makeSidebar() -> NSView {
        categoryPopUp.addItems(withTitles: PreviewCategory.allCases.map(\.title))
        categoryPopUp.target = self
        categoryPopUp.action = #selector(categoryChanged)

        searchField.placeholderString = "Filter"
        searchField.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.stringValue = ""

        let stack = NSStackView(views: [categoryPopUp, searchField, scroll, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return stack
    }

    private func makeDetailPane() -> NSView {
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)

        infoTextView?.isEditable = false
        infoTextView?.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        let stack = NSStackView(views: [imageView, infoScroll])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        imageView.heightAnchor.constraint(
            equalTo: stack.heightAnchor,
            multiplier: 0.55
        ).isActive = true
        return stack
    }

    // MARK: - Catalog load (off main)

    private func loadCatalog(root: GameDataRoot) {
        statusLabel.stringValue = "Loading archives + Skyrim.esm…"
        let fileSystem = VirtualFileSystem(root: root)
        let esmURL = root.dataURL.appending(path: "Skyrim.esm")
        Task.detached(priority: .userInitiated) {
            let loaded = PreviewCatalog.load(fileSystem: fileSystem, esmURL: esmURL)
            await MainActor.run { [weak self] in
                self?.catalogDidLoad(
                    loaded.catalog,
                    fileSystem: fileSystem,
                    localized: loaded.localized
                )
            }
        }
    }

    private func catalogDidLoad(
        _ catalog: PreviewCatalog,
        fileSystem: VirtualFileSystem,
        localized: Bool
    ) {
        self.catalog = catalog
        detailBuilder = PreviewDetailBuilder(fileSystem: fileSystem, localized: localized)
        applyFilter()
    }

    // MARK: - Filtering

    @objc private func categoryChanged() {
        applyFilter()
    }

    private func applyFilter() {
        guard let catalog else { return }
        filterGeneration += 1
        let generation = filterGeneration
        let items = catalog.items(for: selectedCategory)
        let query = searchField.stringValue
        // Small lists (and the no-op empty query) filter inline; scanning
        // the ~870k record rows goes off-main so typing stays responsive.
        if query.isEmpty || items.count < 100_000 {
            show(items: PreviewCatalog.filter(items, query: query))
            return
        }
        Task.detached(priority: .userInitiated) {
            let filtered = PreviewCatalog.filter(items, query: query)
            await MainActor.run { [weak self] in
                guard let self, filterGeneration == generation else { return }
                show(items: filtered)
            }
        }
    }

    private func show(items: [PreviewItem]) {
        visibleItems = items
        tableView.reloadData()
        updateStatus()
    }

    private func updateStatus() {
        guard let catalog else { return }
        var status = "\(visibleItems.count) shown — "
            + "\(catalog.fileCount) archive entries, \(catalog.recordCount) records"
        if !catalog.notes.isEmpty {
            status += " — " + catalog.notes.joined(separator: "; ")
        }
        statusLabel.stringValue = status
        statusLabel.toolTip = status
    }
}

// MARK: - Sidebar table

extension PreviewViewController: NSTableViewDataSource {
    func numberOfRows(in _: NSTableView) -> Int {
        visibleItems.count
    }
}

extension PreviewViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("entryCell")
        let label: NSTextField
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField {
            label = reused
        } else {
            label = NSTextField(labelWithString: "")
            label.identifier = identifier
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.lineBreakMode = .byTruncatingMiddle
        }
        label.stringValue = visibleItems[row].display
        return label
    }

    func tableViewSelectionDidChange(_: Notification) {
        let row = tableView.selectedRow
        guard visibleItems.indices.contains(row), let detailBuilder else { return }
        let detail = detailBuilder.detail(for: visibleItems[row].selection)
        infoTextView?.string = detail.text
        if let image = detail.image {
            imageView.image = NSImage(
                cgImage: image,
                size: NSSize(width: image.width, height: image.height)
            )
        } else {
            imageView.image = nil
        }
    }
}

// MARK: - Filter field

extension PreviewViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_: Notification) {
        applyFilter()
    }
}
