// The launcher window: a page list on the left and the selected page on the
// right. Pages come from `LauncherRegistry`, are built on first selection, and
// stay cached.

import AppKit

final class LauncherViewController: NSSplitViewController {
    private let sidebar = LauncherSidebarViewController()
    private let content = NSViewController()
    private weak var actions: (any LauncherActions)?
    private var pageControllers: [String: NSViewController] = [:]
    private(set) var currentPageID: String?

    init(actions: any LauncherActions) {
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        content.view = NSView()
        content.view.wantsLayer = true
        content.view.layer?.backgroundColor = Theme.windowBackground.cgColor

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 220
        sidebarItem.canCollapse = false
        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: content))
        splitView.dividerStyle = .thin

        sidebar.onSelect = { [weak self] page in self?.show(page) }
        sidebar.select(id: LauncherRegistry.defaultPageID)
    }

    /// Redraws every built page that shows game-folder state.
    func refreshGameFolder() {
        for controller in pageControllers.values {
            (controller as? any LauncherPageRefreshing)?.refreshGameFolder()
        }
    }

    func showPage(id: String) {
        sidebar.select(id: id)
    }

    private func show(_ page: LauncherPageDescriptor) {
        guard let actions, currentPageID != page.id else { return }
        if let current = currentPageID.flatMap({ pageControllers[$0] }) {
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        let controller = pageControllers[page.id] ?? page.makeController(actions)
        pageControllers[page.id] = controller
        currentPageID = page.id
        content.addChild(controller)
        let pageView = controller.view
        pageView.translatesAutoresizingMaskIntoConstraints = false
        content.view.addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: content.view.topAnchor),
            pageView.leadingAnchor.constraint(equalTo: content.view.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: content.view.trailingAnchor),
            pageView.bottomAnchor.constraint(lessThanOrEqualTo: content.view.bottomAnchor)
        ])
    }
}

/// The launcher's page list: a plain source list, one row per registered page.
final class LauncherSidebarViewController: NSViewController {
    var onSelect: ((LauncherPageDescriptor) -> Void)?
    private let tableView = NSTableView()

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityIdentifier("LauncherSidebar")
        tableView.setAccessibilityLabel("Launcher pages")
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.documentView = tableView
        view = scroll
    }

    func select(id: String) {
        guard let row = LauncherRegistry.pages.firstIndex(where: { $0.id == id }) else { return }
        loadViewIfNeeded()
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }
}

extension LauncherSidebarViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in _: NSTableView) -> Int {
        LauncherRegistry.pages.count
    }

    func tableView(_: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        let page = LauncherRegistry.pages[row]
        let cell = NSTableCellView()
        let image = NSImageView(
            image: NSImage(systemSymbolName: page.symbolName, accessibilityDescription: nil)
                ?? NSImage()
        )
        image.contentTintColor = Theme.gold
        let label = NSTextField(labelWithString: page.title)
        label.textColor = Theme.parchment
        cell.imageView = image
        cell.textField = label
        let row = NSStackView(views: [image, label])
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            row.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        cell.setAccessibilityIdentifier(page.sidebarIdentifier)
        return cell
    }

    func tableViewSelectionDidChange(_: Notification) {
        let row = tableView.selectedRow
        guard LauncherRegistry.pages.indices.contains(row) else { return }
        onSelect?(LauncherRegistry.pages[row])
    }
}
