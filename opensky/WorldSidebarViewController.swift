// World-mode shell (M7.1.2): a collapsible source-list sidebar of world
// destinations beside the always-live World MTKView. Selecting a destination
// reveals its controls panel without ever removing the game view from the
// hierarchy, so rendering + streaming keep running. Destinations come from the
// shared DestinationRegistry (issue #98) — adding one never touches this shell.
// AppKit-programmatic to match the codebase (no storyboard). The unified-sidebar
// redesign (issue #98 PR 2) replaces this World-only shell.

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

        sidebarList.onSelect = { [weak self] id in
            self?.content.showDestination(id: id)
        }
        // Default-select the first destination so the surface + its controls
        // are visible on entry (and reachable by UI tests without navigation).
        sidebarList.selectFirst()
    }
}

/// Detail area: the live World view with an optional leading controls panel.
/// The MTKView never leaves the hierarchy; the panel slot collapses to zero
/// width when no destination is selected. Each destination owns its own panel
/// (built once from the registry); they stack in a shared leading slot and only
/// the active one is visible.
final class WorldContentViewController: NSViewController {
    let gameViewController: GameViewController
    private let panelSlot = NSView()
    private var panelWidth: NSLayoutConstraint?
    private var currentID: String?

    /// Registered world-inspector panels, keyed + ordered by registry id.
    private let panels: [(id: String, panel: any InspectorPanel)]

    init(gameViewController: GameViewController) {
        self.gameViewController = gameViewController
        panels = WorldContentViewController.buildPanels(providers: gameViewController)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    /// Builds every world-inspector panel from the registry, wired to the live
    /// renderer bridge. Non-inspector destinations are handled by PR 2's shell.
    private static func buildPanels(
        providers: any WorldControlProviders
    ) -> [(id: String, panel: any InspectorPanel)] {
        let context = WorldPanelContext(providers: providers)
        return DestinationRegistry.worldInspectors.compactMap { descriptor in
            guard case let .worldInspector(makePanel) = descriptor.content else { return nil }
            return (descriptor.id, makePanel(context))
        }
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(gameViewController)
        for entry in panels {
            addChild(entry.panel)
        }

        let gameView = gameViewController.view
        gameView.translatesAutoresizingMaskIntoConstraints = false
        panelSlot.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panelSlot)
        view.addSubview(gameView)

        for entry in panels {
            let panelView = entry.panel.view
            panelView.translatesAutoresizingMaskIntoConstraints = false
            panelSlot.addSubview(panelView)
            NSLayoutConstraint.activate([
                panelView.topAnchor.constraint(equalTo: panelSlot.topAnchor),
                panelView.bottomAnchor.constraint(equalTo: panelSlot.bottomAnchor),
                panelView.leadingAnchor.constraint(equalTo: panelSlot.leadingAnchor),
                panelView.trailingAnchor.constraint(equalTo: panelSlot.trailingAnchor)
            ])
            panelView.isHidden = true
        }

        let width = panelSlot.widthAnchor.constraint(equalToConstant: 0)
        panelWidth = width
        NSLayoutConstraint.activate([
            panelSlot.topAnchor.constraint(equalTo: view.topAnchor),
            panelSlot.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panelSlot.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            width,
            gameView.topAnchor.constraint(equalTo: view.topAnchor),
            gameView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gameView.leadingAnchor.constraint(equalTo: panelSlot.trailingAnchor),
            gameView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    /// Reveals the panel for `id` (hiding the rest) or collapses the slot. Only
    /// the revealed panel inspects; the others stop ticking.
    func showDestination(id: String?) {
        currentID = id
        let active = panel(for: id)
        for entry in panels {
            let isActive = entry.id == id
            entry.panel.view.isHidden = !isActive
            if !isActive {
                entry.panel.stopInspecting()
            }
        }
        let show = active != nil
        panelWidth?.constant = show ? PanelMetrics.panelWidth : 0
        if show, view.window != nil {
            active?.startInspecting()
        } else {
            active?.stopInspecting()
        }
    }

    /// Maps a registry id to its panel (nil collapses the slot).
    private func panel(for id: String?) -> (any InspectorPanel)? {
        guard let id else { return nil }
        return panels.first { $0.id == id }?.panel
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        panel(for: currentID)?.startInspecting()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        for entry in panels {
            entry.panel.stopInspecting()
        }
    }
}

/// Source-list sidebar listing world-inspector destinations; reports selection
/// changes by registry id.
final class SidebarListViewController: NSViewController {
    var onSelect: ((String?) -> Void)?

    private let tableView = NSTableView()
    private let destinations = DestinationRegistry.worldInspectors

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
        onSelect?(destinations[0].id)
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
        onSelect?(destinations.indices.contains(row) ? destinations[row].id : nil)
    }
}
