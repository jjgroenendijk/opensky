// The Save and Load pages: the save list newest first. Saving over a file and
// deleting a file ask first. See docs/engine/system-menu.md.

import Foundation

/// One save in the list, already read from its summary chunk.
nonisolated public struct SaveSlotRow: Equatable, Sendable {
    public let slot: String
    public let title: String
    public let detail: String
    public let savedAt: Date
    public let hasThumbnail: Bool
    /// Set when the file could not be read; it can still be deleted.
    public let error: String?

    public init(
        slot: String, title: String, detail: String, savedAt: Date, hasThumbnail: Bool = false,
        error: String? = nil
    ) {
        self.slot = slot
        self.title = title
        self.detail = detail
        self.savedAt = savedAt
        self.hasThumbnail = hasThumbnail
        self.error = error
    }

    /// The row as the list shows it: title, detail, and whether it has a picture.
    public var listText: String {
        ([title, detail].filter { !$0.isEmpty } + (hasThumbnail ? ["picture"] : []))
            .joined(separator: " · ")
    }
}

nonisolated public enum SaveLoadMode: String, Equatable, Sendable {
    case save, load
}

nonisolated public enum SaveLoadAction: Equatable, Sendable {
    /// Nil writes a new slot.
    case save(slot: String?)
    case load(slot: String)
    case delete(slot: String)
    case back
}

nonisolated public struct SaveLoadPageModel: Equatable, Sendable {
    public static let newSaveTitle = "New Save"

    public let mode: SaveLoadMode
    public private(set) var rows: [SaveSlotRow]
    public private(set) var selectedIndex = 0
    public private(set) var confirmation: ConfirmationModel?
    private var pending: SaveLoadAction?

    public init(mode: SaveLoadMode, rows: [SaveSlotRow]) {
        self.mode = mode
        self.rows = Self.sorted(rows)
    }

    public static func sorted(_ rows: [SaveSlotRow]) -> [SaveSlotRow] {
        rows.sorted { ($0.savedAt, $1.slot) > ($1.savedAt, $0.slot) }
    }

    /// The Save page starts with a New Save row before the files.
    public var titles: [String] {
        (mode == .save ? [Self.newSaveTitle] : []) + rows.map(\.listText)
    }

    public var selectedRow: SaveSlotRow? {
        let index = mode == .save ? selectedIndex - 1 : selectedIndex
        return rows.indices.contains(index) ? rows[index] : nil
    }

    public mutating func replaceRows(_ rows: [SaveSlotRow]) {
        self.rows = Self.sorted(rows)
        selectedIndex = min(selectedIndex, max(0, titles.count - 1))
        confirmation = nil
        pending = nil
    }

    /// Asks before deleting the selected file. Nothing happens on New Save.
    public mutating func requestDelete() {
        guard let row = selectedRow else { return }
        ask("Delete \(row.title)?", then: .delete(slot: row.slot))
    }

    @discardableResult
    public mutating func handle(_ event: MenuInputEvent) -> SaveLoadAction? {
        if var question = confirmation {
            let choice = question.handle(event)
            confirmation = question
            guard let choice else { return nil }
            let action = choice == .chose(0) ? pending : nil
            confirmation = nil
            pending = nil
            return action
        }
        let count = titles.count
        switch event {
        case .move(.up) where count > 0:
            selectedIndex = (selectedIndex + count - 1) % count
        case .move(.down) where count > 0:
            selectedIndex = (selectedIndex + 1) % count
        case .button(.accept):
            return activate()
        case .button(.cancel):
            return .back
        default:
            break
        }
        return nil
    }

    private mutating func activate() -> SaveLoadAction? {
        switch (mode, selectedRow) {
        case (.save, nil):
            return .save(slot: nil)
        case let (.save, .some(row)):
            ask("Save over \(row.title)?", then: .save(slot: row.slot))
            return nil
        case let (.load, .some(row)) where row.error == nil:
            return .load(slot: row.slot)
        case (.load, _):
            return nil
        }
    }

    private mutating func ask(_ question: String, then action: SaveLoadAction) {
        confirmation = ConfirmationModel(question: question)
        pending = action
    }
}
