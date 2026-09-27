// Load Order destination: what plugins.txt the engine found, and the plugin
// order it produced (issue #73). The user can point the engine at a different
// plugins.txt here without knowing a CLI flag, which is the whole reason the
// setting is not environment-only.
//
// Resolution, ordering, and every string in the table live in the engine
// (`PluginLoadOrder`, `PluginLoadOrderReport`); this file is the AppKit shell.

import AppKit

final class LoadOrderViewController: NSViewController {
    /// Located install, set by the shell before the view loads; nil -> the
    /// panel explains why instead of listing plugins.
    var gameDataRoot: GameDataRoot?
    /// Locator failure text shown in-window (the app still launches).
    var startupErrorMessage: String?

    private(set) var rows: [PluginLoadOrderReport.Row] = []

    let pathLabel = NSTextField(labelWithString: "")
    let sourceLabel = NSTextField(labelWithString: "")
    let summaryLabel = NSTextField(labelWithString: "")
    let tableView = NSTableView()
    let chooseControl = NSButton()
    let useDefaultControl = NSButton()
    let reloadControl = NSButton()

    private enum Column: String, CaseIterable {
        case position
        case name
        case origin
        case note

        var title: String {
            switch self {
            case .position: "#"
            case .name: "Plugin"
            case .origin: "Source"
            case .note: "Note"
            }
        }

        var width: CGFloat {
            switch self {
            case .position: 40
            case .name: 260
            case .origin: 110
            case .note: 260
            }
        }
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = makeContentView()
        view.setAccessibilityIdentifier("LoadOrder")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refresh()
    }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        let heading = NSTextField(labelWithString: "Plugin Load Order")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        pathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathLabel.isSelectable = true
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setAccessibilityIdentifier("LoadOrderPathLabel")

        sourceLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        sourceLabel.textColor = Theme.parchmentDim
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.setAccessibilityIdentifier("LoadOrderSourceLabel")

        summaryLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        summaryLabel.textColor = Theme.parchmentDim
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.setAccessibilityIdentifier("LoadOrderStatsLabel")

        let stack = NSStackView(views: [
            heading, pathLabel, sourceLabel, makeButtonRow(), makeTable(), summaryLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.setCustomSpacing(12, after: sourceLabel)
        return stack
    }

    private func makeButtonRow() -> NSView {
        configure(
            chooseControl,
            title: "Choose plugins.txt…",
            identifier: "LoadOrderChooseControl",
            action: #selector(choosePluginsText)
        )
        configure(
            useDefaultControl,
            title: "Search Automatically",
            identifier: "LoadOrderUseDefaultControl",
            action: #selector(useDefaultPluginsText)
        )
        configure(
            reloadControl,
            title: "Reload",
            identifier: "LoadOrderReloadControl",
            action: #selector(reloadOrder)
        )

        let row = NSStackView(views: [chooseControl, useDefaultControl, reloadControl, NSView()])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func configure(
        _ button: NSButton,
        title: String,
        identifier: String,
        action: Selector
    ) {
        button.bezelStyle = .rounded
        button.title = title
        button.target = self
        button.action = action
        button.setAccessibilityIdentifier(identifier)
    }

    private func makeTable() -> NSView {
        for column in Column.allCases {
            let tableColumn = NSTableColumn(
                identifier: NSUserInterfaceItemIdentifier(column.rawValue)
            )
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableView.addTableColumn(tableColumn)
        }
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityIdentifier("LoadOrderTable")

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        return scroll
    }

    // MARK: - State

    /// Re-resolves the load order and repaints. Cheap enough for the main
    /// thread: a directory listing plus two short text files, no plugin is
    /// opened here.
    private func refresh(problem: String? = nil) {
        guard isViewLoaded else { return }
        guard let gameDataRoot else {
            rows = []
            tableView.reloadData()
            pathLabel.stringValue = "Not located"
            sourceLabel.stringValue = startupErrorMessage ?? "Game data not located."
            sourceLabel.textColor = .systemRed
            summaryLabel.stringValue = ""
            return
        }
        let report = PluginLoadOrderReport(
            resolution: PluginLoadOrder.resolve(root: gameDataRoot)
        )
        rows = report.rows
        tableView.reloadData()
        pathLabel.stringValue = report.pluginsTextPath
        pathLabel.toolTip = report.pluginsTextPath
        let note = problem ?? report.problem ?? report.sourceNote
        sourceLabel.stringValue = note
        sourceLabel.toolTip = note
        sourceLabel.textColor = problem == nil && report.problem == nil
            ? Theme.parchmentDim
            : .systemOrange
        summaryLabel.stringValue = report.summary
    }

    // MARK: - Actions

    @objc private func choosePluginsText() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the plugins.txt holding your load order."
        panel.prompt = "Use File"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let path = url.path(percentEncoded: false)
            do {
                try PluginsTextLocator.saveUserChoice(path: path)
                refresh()
            } catch {
                refresh(problem: error.localizedDescription)
            }
        }
    }

    @objc private func useDefaultPluginsText() {
        PluginsTextLocator.clearUserChoice()
        refresh()
    }

    @objc private func reloadOrder() {
        refresh()
    }
}

// MARK: - Table

extension LoadOrderViewController: NSTableViewDataSource {
    func numberOfRows(in _: NSTableView) -> Int {
        rows.count
    }
}

extension LoadOrderViewController: NSTableViewDelegate {
    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard
            let tableColumn,
            let column = Column(rawValue: tableColumn.identifier.rawValue),
            rows.indices.contains(row)
        else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("loadOrderCell")
        let label: NSTextField
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField {
            label = reused
        } else {
            label = NSTextField(labelWithString: "")
            label.identifier = identifier
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.lineBreakMode = .byTruncatingMiddle
        }
        let entry = rows[row]
        label.stringValue = switch column {
        case .position: entry.position
        case .name: entry.name
        case .origin: entry.origin
        case .note: entry.note
        }
        return label
    }
}

// MARK: - Shell integration

/// Lets a Settings data-root change reach the cached panel in place, the same
/// way the Asset Browser takes one.
extension LoadOrderViewController: FullContentReloadable {
    func reloadFullContent(context: FullContentContext) {
        gameDataRoot = context.gameDataRoot
        startupErrorMessage = context.startupErrorMessage
        refresh()
    }
}
