// The Settings page of the system menu: the category list (Gameplay, Display,
// Audio), then one category's option rows. Left and right adjust the selected
// row. The values live in the settings store; this holds only the page state.

import Foundation
import OpenSkyGameData

nonisolated public enum SettingsPageAction: Equatable, Sendable {
    case adjust(PlayerSettingID, direction: Int)
    /// Leave the Settings page.
    case back
}

nonisolated public struct SettingsPageModel: Equatable, Sendable {
    public static let categories: [PlayerSettingGroup] = [.gameplay, .display, .audio]

    public let catalog: [PlayerSettingGroup: [PlayerSettingID]]
    public private(set) var categoryIndex = 0
    /// Nil while the category list shows.
    public private(set) var openGroup: PlayerSettingGroup?
    public private(set) var rowIndex = 0

    public init(catalog: PlayerSettingsCatalog) {
        var rows: [PlayerSettingGroup: [PlayerSettingID]] = [:]
        for group in Self.categories {
            rows[group] = catalog.definitions(in: group).map(\.id)
        }
        self.catalog = rows
    }

    public var rows: [PlayerSettingID] {
        openGroup.flatMap { catalog[$0] } ?? []
    }

    public var selectedRow: PlayerSettingID? {
        rows.indices.contains(rowIndex) ? rows[rowIndex] : nil
    }

    public var selectedCategory: PlayerSettingGroup {
        Self.categories[categoryIndex]
    }

    public mutating func openCategory(_ group: PlayerSettingGroup) {
        guard let index = Self.categories.firstIndex(of: group) else { return }
        categoryIndex = index
        openGroup = group
        rowIndex = 0
    }

    @discardableResult
    public mutating func handle(_ event: MenuInputEvent) -> SettingsPageAction? {
        if openGroup == nil {
            return handleCategories(event)
        }
        switch event {
        case .move(.up):
            rowIndex = wrapped(rowIndex - 1, count: rows.count)
        case .move(.down):
            rowIndex = wrapped(rowIndex + 1, count: rows.count)
        case .move(.left):
            return selectedRow.map { .adjust($0, direction: -1) }
        case .move(.right), .button(.accept):
            return selectedRow.map { .adjust($0, direction: 1) }
        case .button(.cancel):
            openGroup = nil
        case .pointer, .release:
            break
        }
        return nil
    }

    private mutating func handleCategories(_ event: MenuInputEvent) -> SettingsPageAction? {
        switch event {
        case .move(.up):
            categoryIndex = wrapped(categoryIndex - 1, count: Self.categories.count)
        case .move(.down):
            categoryIndex = wrapped(categoryIndex + 1, count: Self.categories.count)
        case .button(.accept), .move(.right):
            openCategory(selectedCategory)
        case .button(.cancel):
            return .back
        case .move(.left), .pointer, .release:
            break
        }
        return nil
    }

    private func wrapped(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index % count + count) % count
    }
}
