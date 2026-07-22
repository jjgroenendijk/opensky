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

/// A destination controls panel with a 2 Hz live readout the content area can
/// start/stop as the panel is revealed or the World view leaves screen.
protocol WorldInspectorPanel: NSViewController {
    func startInspecting()
    func stopInspecting()
}

extension EnvironmentPanelViewController: WorldInspectorPanel {}
extension UILabPanelViewController: WorldInspectorPanel {}

/// Detail area: the live World view with an optional leading controls panel.
/// The MTKView never leaves the hierarchy; the panel slot collapses to zero
/// width when no destination is selected. Each destination owns its own panel;
/// they stack in a shared leading slot and only the active one is visible.
final class WorldContentViewController: NSViewController {
    let gameViewController: GameViewController
    private let environmentPanel = EnvironmentPanelViewController()
    private let uiLabPanel = UILabPanelViewController()
    private let panelSlot = NSView()
    private var panelWidth: NSLayoutConstraint?
    private var currentDestination: WorldDestination?

    /// Every destination panel, in row order (matches WorldDestination).
    private var panels: [WorldInspectorPanel] {
        [environmentPanel, uiLabPanel]
    }

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
        for panel in panels {
            addChild(panel)
        }

        let gameView = gameViewController.view
        gameView.translatesAutoresizingMaskIntoConstraints = false
        panelSlot.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panelSlot)
        view.addSubview(gameView)

        for panel in panels {
            let panelView = panel.view
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

    /// Points every destination panel at the live renderer bridge.
    func wireProvider() {
        environmentPanel.provider = gameViewController
        environmentPanel.weatherProvider = gameViewController
        environmentPanel.animationProvider = gameViewController
        environmentPanel.particleProvider = gameViewController
        environmentPanel.precipitationProvider = gameViewController
        environmentPanel.grassProvider = gameViewController
        uiLabPanel.provider = gameViewController
    }

    /// Reveals the panel for `destination` (hiding the rest) or collapses the
    /// slot. Only the revealed panel inspects; the others stop ticking.
    func showDestination(_ destination: WorldDestination?) {
        currentDestination = destination
        let active = panel(for: destination)
        for panel in panels {
            let isActive = panel === active
            panel.view.isHidden = !isActive
            if !isActive {
                panel.stopInspecting()
            }
        }
        let show = active != nil
        panelWidth?.constant = show ? 300 : 0
        if show, view.window != nil {
            active?.startInspecting()
        } else {
            active?.stopInspecting()
        }
    }

    /// Maps a destination to its panel (nil collapses the slot).
    private func panel(for destination: WorldDestination?) -> WorldInspectorPanel? {
        switch destination {
        case .environment: environmentPanel
        case .uiLab: uiLabPanel
        case nil: nil
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        panel(for: currentDestination)?.startInspecting()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        for panel in panels {
            panel.stopInspecting()
        }
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
