// Unified app sidebar (issue #98 PR 2): a source-list NSOutlineView grouping
// every registered destination under its section header (Finder/Xcode style).
// Selection reports the destination descriptor; group rows are not selectable.
// Rows come from the shared DestinationRegistry — adding a destination never
// touches this controller.

import AppKit

/// Registry -> sidebar structure, AppKit-free so grouping/order and the
/// default selection are unit-testable (AppSidebarModelTests).
enum AppSidebarModel {
    struct Group {
        let section: SidebarSection
        let destinations: [DestinationDescriptor]
    }

    /// Sections in declaration order, each with its destinations in registry
    /// order; empty sections are dropped.
    static func groups(
        from destinations: [DestinationDescriptor] = DestinationRegistry.all
    ) -> [Group] {
        SidebarSection.allCases.compactMap { section in
            let members = destinations.filter { $0.section == section }
            return members.isEmpty ? nil : Group(section: section, destinations: members)
        }
    }
}

final class AppSidebarViewController: NSViewController {
    var onSelect: ((DestinationDescriptor) -> Void)?
    var isDestinationOverridden: ((String) -> Bool)?

    private let outlineView = NSOutlineView()

    /// Outline items need stable identity, so the model is wrapped in classes
    /// built once.
    private final class GroupItem {
        let group: AppSidebarModel.Group
        let children: [DestinationItem]

        init(group: AppSidebarModel.Group) {
            self.group = group
            children = group.destinations.map { DestinationItem(descriptor: $0) }
        }
    }

    private final class DestinationItem {
        let descriptor: DestinationDescriptor

        init(descriptor: DestinationDescriptor) {
            self.descriptor = descriptor
        }
    }

    private final class DestinationCell: NSTableCellView {
        let overrideIndicator = NSTextField(labelWithString: "●")
    }

    private lazy var groups = AppSidebarModel.groups().map { GroupItem(group: $0) }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("destination"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.floatsGroupRows = true
        outlineView.rowSizeStyle = .default
        outlineView.indentationPerLevel = 0
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.setAccessibilityIdentifier("AppSidebar")
        outlineView.setAccessibilityLabel("Destinations")

        scroll.documentView = outlineView
        view = scroll
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        outlineView.expandItem(nil, expandChildren: true)
    }

    /// Selects the destination row for `id` and reports it (launch default +
    /// Settings-reload re-apply).
    func select(id: String) {
        guard let item = destinationItem(id: id) else { return }
        let row = outlineView.row(forItem: item)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    /// Re-queries visible destination rows without rebuilding the sidebar model.
    func refreshOverrideIndicators() {
        for group in groups {
            for child in group.children {
                outlineView.reloadItem(child)
            }
        }
    }

    /// Test seam for the accessibility-backed row projection.
    func overrideIndicatorIsVisible(destinationID: String) -> Bool? {
        guard let item = destinationItem(id: destinationID) else { return nil }
        let row = outlineView.row(forItem: item)
        guard
            row >= 0,
            let cell = outlineView.view(
                atColumn: 0, row: row, makeIfNecessary: true
            ) as? DestinationCell
        else { return nil }
        return !cell.overrideIndicator.isHidden
    }

    private func destinationItem(id: String) -> DestinationItem? {
        for group in groups {
            if let match = group.children.first(where: { $0.descriptor.id == id }) {
                return match
            }
        }
        return nil
    }
}

extension AppSidebarViewController: NSOutlineViewDataSource {
    func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        switch item {
        case nil: groups.count
        case let group as GroupItem: group.children.count
        default: 0
        }
    }

    func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        switch item {
        case nil: groups[index]
        case let group as GroupItem: group.children[index]
        default: NSNull()
        }
    }

    func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is GroupItem
    }
}

extension AppSidebarViewController: NSOutlineViewDelegate {
    func outlineView(_: NSOutlineView, isGroupItem item: Any) -> Bool {
        item is GroupItem
    }

    func outlineView(_: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        item is DestinationItem
    }

    func outlineView(_: NSOutlineView, viewFor _: NSTableColumn?, item: Any) -> NSView? {
        switch item {
        case let group as GroupItem:
            let cell = makeCell(
                id: "SidebarGroupCell",
                text: group.group.section.title,
                symbolName: nil
            )
            cell.textField?.attributedStringValue = Theme.headingAttributed(
                group.group.section.title,
                size: 11,
                color: Theme.gold
            )
            return cell
        case let destination as DestinationItem:
            let descriptor = destination.descriptor
            let cell = makeDestinationCell(descriptor)
            cell.textField?.textColor = Theme.parchment
            cell.imageView?.contentTintColor = Theme.gold
            cell.setAccessibilityIdentifier(descriptor.sidebarIdentifier)
            cell.textField?.setAccessibilityIdentifier(descriptor.sidebarIdentifier)
            cell.overrideIndicator.isHidden =
                isDestinationOverridden?(descriptor.id) != true
            cell.overrideIndicator.setAccessibilityIdentifier(
                "\(descriptor.sidebarIdentifier)-OverrideIndicator"
            )
            return cell
        default:
            return nil
        }
    }

    func outlineViewSelectionDidChange(_: Notification) {
        let row = outlineView.selectedRow
        guard
            row >= 0,
            let item = outlineView.item(atRow: row) as? DestinationItem
        else { return }
        onSelect?(item.descriptor)
    }

    /// Builds/reuses a source-list cell; destination rows carry an SF Symbol.
    private func makeCell(id: String, text: String, symbolName: String?) -> NSTableCellView {
        let identifier = NSUserInterfaceItemIdentifier(id)
        if
            let cell = outlineView.makeView(
                withIdentifier: identifier, owner: self
            ) as? NSTableCellView
        {
            cell.textField?.stringValue = text
            cell.imageView?.image = symbolName.flatMap {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil)
            }
            return cell
        }
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        var leading = cell.leadingAnchor
        if let symbolName {
            let image = NSImageView(
                image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
                    ?? NSImage()
            )
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 18)
            ])
            leading = image.trailingAnchor
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leading, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func makeDestinationCell(_ descriptor: DestinationDescriptor) -> DestinationCell {
        let identifier = NSUserInterfaceItemIdentifier("SidebarDestinationCell")
        if
            let cell = outlineView.makeView(
                withIdentifier: identifier, owner: self
            ) as? DestinationCell
        {
            cell.textField?.stringValue = descriptor.title
            cell.imageView?.image = NSImage(
                systemSymbolName: descriptor.symbolName,
                accessibilityDescription: nil
            )
            return cell
        }

        let cell = DestinationCell()
        cell.identifier = identifier
        let image = NSImageView(
            image: NSImage(
                systemSymbolName: descriptor.symbolName,
                accessibilityDescription: nil
            ) ?? NSImage()
        )
        image.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(image)
        cell.imageView = image

        let label = NSTextField(labelWithString: descriptor.title)
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label

        let indicator = cell.overrideIndicator
        indicator.textColor = Theme.gold
        indicator.toolTip = "This destination has controls that differ from their defaults"
        indicator.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(indicator)

        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            indicator.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor),
            indicator.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            indicator.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
}
