public import Foundation
import OpenSkyFormatsCore

/// The list row of a save: who, where, and how long.
nonisolated public struct SaveSummary: Equatable, Sendable {
    public var characterName: String
    public var level: Int
    public var raceName: String
    public var locationName: String
    /// Real seconds played across sessions, not game time.
    public var playSeconds: Double

    public init(
        characterName: String, level: Int, raceName: String, locationName: String,
        playSeconds: Double
    ) {
        self.characterName = characterName
        self.level = level
        self.raceName = raceName
        self.locationName = locationName
        self.playSeconds = playSeconds
    }
}

/// A small RGBA8 picture of the frame at save time, rows top first.
nonisolated public struct SaveThumbnail: Equatable, Sendable {
    public static let maximumSide = 512

    public let width: Int
    public let height: Int
    public let rgba: Data

    /// Nil when the size is out of range or the bytes do not fill it.
    public init?(width: Int, height: Int, rgba: Data) {
        guard
            (1 ... Self.maximumSide).contains(width), (1 ... Self.maximumSide).contains(height),
            rgba.count == width * height * 4
        else { return nil }
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

/// What the list reads from one file: header, summary, and picture.
nonisolated public struct OpenSkySaveSummaryFile: Equatable, Sendable {
    public let metadata: SaveCreationMetadata
    public let summary: SaveSummary?
    public let thumbnail: SaveThumbnail?

    public init(
        metadata: SaveCreationMetadata,
        summary: SaveSummary?,
        thumbnail: SaveThumbnail?
    ) {
        self.metadata = metadata
        self.summary = summary
        self.thumbnail = thumbnail
    }
}
