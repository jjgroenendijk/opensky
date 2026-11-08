import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering

nonisolated public struct RaceMenuSnapshot: Equatable, Sendable {
    public let isLimited: Bool
    public let rows: [String]
    public let selectedIndex: Int
    public let lastResult: String?
    /// The player's face now: weight, the slider values that are not 0, parts, and tints.
    public let face: [String]
    public let movie: TitleMenuMovieSnapshot

    public init(
        isLimited: Bool,
        rows: [String],
        selectedIndex: Int,
        lastResult: String?,
        face: [String] = [],
        movie: TitleMenuMovieSnapshot = .init()
    ) {
        self.face = face
        self.movie = movie
        self.isLimited = isLimited
        self.rows = rows
        self.selectedIndex = selectedIndex
        self.lastResult = lastResult
    }
}
