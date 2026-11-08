public import Foundation
import OpenSkyGameData

/// Who a save belongs to, as its summary records it.
nonisolated public struct SaveSlotCharacter: Equatable, Sendable {
    public let name: String
    public let race: String
    public let level: Int
    public let playTime: String

    public init(name: String, race: String, level: Int, playTime: String) {
        self.name = name
        self.race = race
        self.level = level
        self.playTime = playTime
    }
}

/// A save's picture: straight-alpha RGBA, row by row.
nonisolated public struct SaveSlotPicture: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let rgba: Data

    public init(width: Int, height: Int, rgba: Data) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

/// One save in the list, already read from its summary chunk.
nonisolated public struct SaveSlotRow: Equatable, Sendable {
    public let slot: String
    public let title: String
    public let detail: String
    public let savedAt: Date
    public let hasThumbnail: Bool
    /// Set when the file could not be read; it can still be deleted.
    public let error: String?
    public let character: SaveSlotCharacter?
    public let picture: SaveSlotPicture?
    /// A Skyrim `.ess` save: it loads through an import and is never written or deleted.
    public let isImport: Bool

    public init(
        slot: String, title: String, detail: String, savedAt: Date, hasThumbnail: Bool = false,
        error: String? = nil, character: SaveSlotCharacter? = nil, picture: SaveSlotPicture? = nil,
        isImport: Bool = false
    ) {
        self.slot = slot
        self.title = title
        self.detail = detail
        self.savedAt = savedAt
        self.hasThumbnail = hasThumbnail
        self.error = error
        self.character = character
        self.picture = picture
        self.isImport = isImport
    }

    /// The row as the list shows it: title, detail, and whether it has a picture.
    public var listText: String {
        ([title, detail].filter { !$0.isEmpty } + (hasThumbnail ? ["picture"] : []))
            .joined(separator: " · ")
    }
}
