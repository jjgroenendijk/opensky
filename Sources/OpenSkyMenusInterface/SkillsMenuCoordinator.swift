import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData

nonisolated public struct SkillsMenuSnapshot: Equatable, Sendable {
    public let page: String
    /// The rows the engine fallback would draw, one per choice of this page.
    public let rows: [String]
    public let selectedIndex: Int?
    public let movie: TitleMenuMovieSnapshot
    public let isSkyEnabled: Bool
    /// True while the level-up movie is drawn over the stats movie.
    public let isLevelUpMovieLoaded: Bool
    /// The perk sky's state, such as "812 draws, slot 3, tree view"; nil before it shows.
    public let sky: String?

    public init(
        page: String = "Closed",
        rows: [String] = [],
        selectedIndex: Int? = nil,
        movie: TitleMenuMovieSnapshot = .init(),
        isSkyEnabled: Bool = true,
        isLevelUpMovieLoaded: Bool = false,
        sky: String? = nil
    ) {
        self.page = page
        self.rows = rows
        self.selectedIndex = selectedIndex
        self.movie = movie
        self.isSkyEnabled = isSkyEnabled
        self.isLevelUpMovieLoaded = isLevelUpMovieLoaded
        self.sky = sky
    }
}
