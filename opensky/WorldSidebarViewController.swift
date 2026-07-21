// World-mode shell (M7.1.2): a collapsible source-list sidebar of
// WorldDestinations beside the always-live World MTKView. Selecting a
// destination reveals its controls panel without ever removing the game view
// from the hierarchy, so rendering + streaming keep running. First destination
// is Environment (sun-shadow controls); future milestones append to
// WorldDestination and swap the detail panel. AppKit-programmatic to match the
// codebase (no storyboard).

import AppKit

final class WorldSidebarViewController: NSSplitViewController {
    private let sidebarList = SidebarListViewController()
    private let content: WorldContentViewController

    /// The embedded live World controller (screenshot + reload target).
    var gameViewController: GameViewController {
        content.gameViewController
    }

    init(gameViewController: GameViewController) {
        content = WorldContentViewController(gameViewController: gameViewController)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarList)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 260
        sidebarItem.canCollapse = true

        let contentItem = NSSplitViewItem(viewController: content)

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        splitView.dividerStyle = .thin

        content.wireProvider()
        sidebarList.onSelect = { [weak self] destination in
            self?.content.showDestination(destination)
        }
        // Default-select the first destination so the surface + its controls
        // are visible on entry (and reachable by UI tests without navigation).
        sidebarList.selectFirst()
    }
}

/// Detail area: the live World view with an optional leading controls panel.
/// The MTKView never leaves the hierarchy; the panel collapses to zero width
/// when no destination is selected.
final class WorldContentViewController: NSViewController {
    let gameViewController: GameViewController
    private let panel = EnvironmentPanelViewController()
    private var panelWidth: NSLayoutConstraint?
    private var currentDestination: WorldDestination?

    init(gameViewController: GameViewController) {
        self.gameViewController = gameViewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(gameViewController)
        addChild(panel)

        let gameView = gameViewController.view
        let panelView = panel.view
        gameView.translatesAutoresizingMaskIntoConstraints = false
        panelView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panelView)
        view.addSubview(gameView)

        let width = panelView.widthAnchor.constraint(equalToConstant: 0)
        panelWidth = width
        NSLayoutConstraint.activate([
            panelView.topAnchor.constraint(equalTo: view.topAnchor),
            panelView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panelView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            width,
            gameView.topAnchor.constraint(equalTo: view.topAnchor),
            gameView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gameView.leadingAnchor.constraint(equalTo: panelView.trailingAnchor),
            gameView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        panelView.isHidden = true
    }

    /// Points the panel at the live renderer bridge.
    func wireProvider() {
        panel.provider = gameViewController
        panel.weatherProvider = gameViewController
    }

    /// Reveals the panel for `destination` (only Environment today) or hides it.
    func showDestination(_ destination: WorldDestination?) {
        currentDestination = destination
        let show = destination == .environment
        panel.view.isHidden = !show
        panelWidth?.constant = show ? 300 : 0
        if show, view.window != nil {
            panel.startInspecting()
        } else {
            panel.stopInspecting()
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if currentDestination == .environment {
            panel.startInspecting()
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        panel.stopInspecting()
    }
}

/// Source-list sidebar listing WorldDestinations; reports selection changes.
final class SidebarListViewController: NSViewController {
    var onSelect: ((WorldDestination?) -> Void)?

    private let tableView = NSTableView()
    private let destinations = WorldDestination.allCases

    override func loadView() {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("destination"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityIdentifier("WorldSidebar")
        tableView.setAccessibilityLabel("World destinations")

        scroll.documentView = tableView
        view = scroll
    }

    /// Selects the first destination and reports it.
    func selectFirst() {
        guard !destinations.isEmpty else { return }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        onSelect?(destinations[0])
    }

    private static func makeCell(id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
}

extension SidebarListViewController: NSTableViewDataSource {
    func numberOfRows(in _: NSTableView) -> Int {
        destinations.count
    }
}

extension SidebarListViewController: NSTableViewDelegate {
    func tableView(
        _ tableView: NSTableView,
        viewFor _: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard destinations.indices.contains(row) else { return nil }
        let destination = destinations[row]
        let id = NSUserInterfaceItemIdentifier("SidebarCell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView
            ?? Self.makeCell(id: id)
        cell.textField?.stringValue = destination.title
        cell.setAccessibilityIdentifier(destination.sidebarIdentifier)
        cell.textField?.setAccessibilityIdentifier(destination.sidebarIdentifier)
        return cell
    }

    func tableViewSelectionDidChange(_: Notification) {
        let row = tableView.selectedRow
        onSelect?(destinations.indices.contains(row) ? destinations[row] : nil)
    }
}
