// The launcher window: a page list on the left and the selected page on the
// right. Pages come from `LauncherRegistry`, are built on first selection, and
// stay cached.

import AppKit
import OpenSkyWorld

final class LauncherViewController: NSSplitViewController {
    private let sidebar = LauncherSidebarViewController()
    private let content = NSViewController()
    private let context: LauncherContext
    private var pageControllers: [String: NSViewController] = [:]
    private(set) var currentPageID: String?

    init(actions: any LauncherActions) {
        context = LauncherContext(actions: actions)
        super.init(nibName: nil, bundle: nil)
        context.showPage = { [weak self] id in self?.showPage(id: id) }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        content.view = NSView()
        content.view.wantsLayer = true
        content.view.layer?.backgroundColor = LauncherStyle.background.cgColor

        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.minimumThickness = 210
        sidebarItem.maximumThickness = 260
        sidebarItem.canCollapse = false
        sidebarItem.holdingPriority = .defaultHigh
        addSplitViewItem(sidebarItem)
        let contentItem = NSSplitViewItem(viewController: content)
        contentItem.minimumThickness = LauncherPageLayout.minimumPageWidth
        addSplitViewItem(contentItem)
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

    /// Brings the launch page forward, where the load is drawn.
    func beginLoad() {
        showPage(id: LauncherRegistry.defaultPageID)
        launchPage?.showLoad(WorldLoadTimeline(), elapsed: .zero)
    }

    func showLoad(_ timeline: WorldLoadTimeline, elapsed: Duration) {
        launchPage?.showLoad(timeline, elapsed: elapsed)
    }

    func endLoad() {
        launchPage?.endLoad()
    }

    private var launchPage: LaunchPageViewController? {
        pageControllers[LauncherRegistry.defaultPageID] as? LaunchPageViewController
    }

    private func show(_ page: LauncherPageDescriptor) {
        guard currentPageID != page.id else { return }
        if let current = currentPageID.flatMap({ pageControllers[$0] }) {
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        let controller = pageControllers[page.id] ?? page.makeController(context)
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
            pageView.bottomAnchor.constraint(equalTo: content.view.bottomAnchor)
        ])
    }
}

/// The launcher's page list, drawn like the mod list of the SkyUI menu: black,
/// grey names, and the chosen page in white on a band with a bar at its edge.
final class LauncherSidebarViewController: NSViewController {
    var onSelect: ((LauncherPageDescriptor) -> Void)?
    private let tableView = NSTableView()

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = LauncherStyle.sidebarBackground
        tableView.rowHeight = 40
        tableView.intercellSpacing = .zero
        tableView.gridStyleMask = []
        tableView.focusRingType = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityIdentifier("LauncherSidebar")
        tableView.setAccessibilityLabel("Launcher pages")
        let scroll = NSScrollView()
        scroll.drawsBackground = true
        scroll.backgroundColor = LauncherStyle.sidebarBackground
        scroll.documentView = tableView
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 24, left: 0, bottom: 0, right: 0)
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

    func tableView(_: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
        LauncherSidebarRowView()
    }

    func tableView(_: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        let page = LauncherRegistry.pages[row]
        let cell = NSTableCellView()
        let image = NSImageView(
            image: NSImage(systemSymbolName: page.symbolName, accessibilityDescription: nil)
                ?? NSImage()
        )
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let label = NSTextField(labelWithString: page.title)
        label.font = LauncherStyle.font(17)
        label.lineBreakMode = .byTruncatingTail
        cell.imageView = image
        cell.textField = label
        let stack = NSStackView(views: [image, label])
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 20),
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        colour(cell, selected: tableView.selectedRow == row)
        // A plain cell view is not an accessibility element, so its id would not reach
        // UI tests; expose the row as one element named by its title.
        cell.setAccessibilityElement(true)
        cell.setAccessibilityRole(.cell)
        cell.setAccessibilityLabel(label.stringValue)
        cell.setAccessibilityIdentifier(page.sidebarIdentifier)
        return cell
    }

    func tableViewSelectionDidChange(_: Notification) {
        let row = tableView.selectedRow
        tableView.enumerateAvailableRowViews { rowView, index in
            if let cell = rowView.view(atColumn: 0) as? NSTableCellView {
                colour(cell, selected: index == row)
            }
        }
        guard LauncherRegistry.pages.indices.contains(row) else { return }
        onSelect?(LauncherRegistry.pages[row])
    }

    private func colour(_ cell: NSTableCellView, selected: Bool) {
        let colour = selected ? LauncherStyle.text : LauncherStyle.textDim
        cell.textField?.textColor = colour
        cell.imageView?.contentTintColor = colour
    }
}

/// The chosen page's band: a faint fill and a white bar on the left edge.
final class LauncherSidebarRowView: NSTableRowView {
    override func drawSelection(in _: NSRect) {
        LauncherStyle.highlight.setFill()
        bounds.fill()
        LauncherStyle.text.setFill()
        NSRect(x: 0, y: 6, width: 3, height: bounds.height - 12).fill()
    }

    override var isEmphasized: Bool {
        get { false }
        set { _ = newValue }
    }
}
