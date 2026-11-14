// The place picker of the Launch page: a search field over the places of the install.
// With no search text, the places used last come first. `StartPlaceList` holds the
// search rule; this file only shows it.

import AppKit
import OpenSkyLaunch

final class StartPlacePickerViewController: NSViewController, NSTableViewDataSource,
    NSTableViewDelegate, NSSearchFieldDelegate
{
    private static let size = NSSize(width: 460, height: 380)
    private static let nameColumn = NSUserInterfaceItemIdentifier("name")
    private static let detailColumn = NSUserInterfaceItemIdentifier("detail")

    private let list: StartPlaceList
    private let recent: [StartPlace]
    private let onPick: (StartPlace) -> Void
    private let searchField = NSSearchField()
    private let table = NSTableView()
    private(set) var rows: [StartPlace] = []

    init(
        list: StartPlaceList, recent: [LaunchRecentPlace], onPick: @escaping (StartPlace) -> Void
    ) {
        self.list = list
        self.recent = recent.compactMap { list.place(for: $0.start) }
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        searchField.placeholderString = "Search \(list.places.count) places"
        searchField.delegate = self
        searchField.setAccessibilityIdentifier("LaunchPlaceSearchControl")
        for (identifier, title, width) in [
            (Self.nameColumn, "Place", 250.0), (Self.detailColumn, "Where", 170.0)
        ] {
            let column = NSTableColumn(identifier: identifier)
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(pick)
        table.usesAlternatingRowBackgroundColors = true
        table.setAccessibilityIdentifier("LaunchPlaceTable")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        let stack = NSStackView(views: [searchField, scroll])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        stack.setFrameSize(Self.size)
        view = stack
        preferredContentSize = Self.size
        show(query: "")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        unsafe view.window?.makeFirstResponder(searchField)
    }

    /// The places used last come first while nothing is typed.
    func show(query: String) {
        let found = list.search(query)
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            rows = recent + found.filter { place in !recent.contains(place) }
        } else {
            rows = found
        }
        table.reloadData()
    }

    func controlTextDidChange(_: Notification) {
        show(query: searchField.stringValue)
    }

    /// Return in the search field picks the first place.
    func control(_: NSControl, textView _: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)), let first = rows.first else {
            return false
        }
        onPick(first)
        return true
    }

    func numberOfRows(in _: NSTableView) -> Int {
        rows.count
    }

    func tableView(_: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let place = rows[row]
        let isName = column?.identifier == Self.nameColumn
        let label = NSTextField(labelWithString: isName ? place.name : place.detail)
        label.lineBreakMode = .byTruncatingTail
        label.textColor = isName ? .labelColor : .secondaryLabelColor
        label.toolTip = place.editorID ?? place.start.storedValue
        return label
    }

    @objc private func pick() {
        guard rows.indices.contains(table.clickedRow) else { return }
        onPick(rows[table.clickedRow])
    }
}
