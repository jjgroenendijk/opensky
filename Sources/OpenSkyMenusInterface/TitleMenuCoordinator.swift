import Foundation
import OpenSkyGameData
import OpenSkyRendering

nonisolated public struct TitleMenuSnapshot: Equatable, Sendable {
    public let rows: [String]
    public let selectedIndex: Int
    public let isLoadPageOpen: Bool
    public let lastResult: String?
    public let movie: TitleMenuMovieSnapshot

    public init(
        rows: [String],
        selectedIndex: Int,
        isLoadPageOpen: Bool,
        lastResult: String?,
        movie: TitleMenuMovieSnapshot = TitleMenuMovieSnapshot()
    ) {
        self.rows = rows
        self.selectedIndex = selectedIndex
        self.isLoadPageOpen = isLoadPageOpen
        self.lastResult = lastResult
        self.movie = movie
    }
}

nonisolated public struct TitleMenuMovieSnapshot: Equatable, Sendable {
    public let isLoaded: Bool
    public let error: String?
    public let rows: [String]
    public let selectedIndex: Int?
    public let state: String?

    public init(
        isLoaded: Bool = false,
        error: String? = nil,
        rows: [String] = [],
        selectedIndex: Int? = nil,
        state: String? = nil
    ) {
        self.isLoaded = isLoaded
        self.error = error
        self.rows = rows
        self.selectedIndex = selectedIndex
        self.state = state
    }
}
