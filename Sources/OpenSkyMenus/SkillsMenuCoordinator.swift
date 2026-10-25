// Opens the skills menu on the menu stack, routes keys to `SkillsMenuModel`, and
// carries out its spends through `SkillsMenuSource`. It shows the vanilla level-up
// movie while a pick is owed and the stats movie after; see docs/engine/skills-menu.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyProgressionInterface

public protocol SkillsMenuWorld: SWFLayerWorld {
    var skillsMenuSource: (any SkillsMenuSource)? { get }
    var menuInputConsumer: (any MenuInputConsumer)? { get }
    /// The perk sky's meshes; nil without game data.
    var perkSkySource: PerkSkySource? { get }
    var perkSkySettings: PerkSkySettings { get }
}

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

public final class SkillsMenuCoordinator {
    public static let identifier: MenuIdentifier = "StatsMenu"

    public internal(set) var model: SkillsMenuModel?
    public private(set) var movieEnabled = true
    public internal(set) var skyEnabled = true
    /// True while the sky plays `CameraOutro` after a close; input waits.
    public internal(set) var isClosing = false
    var framePacer = MenuMovieFramePacer()
    /// Buttons the level-up movie pressed, applied after it returns.
    var pendingChoices: [ActorValueKind] = []
    var levelUpShown = false
    var sky = PerkSkyState()
    let movies: SWFMovieSource?
    let hud: HUDCoordinator?
    private let menuMode: MenuModeController
    weak let world: (any SkillsMenuWorld)?

    public init(
        menuMode: MenuModeController, movies: SWFMovieSource? = nil, hud: HUDCoordinator? = nil,
        world: (any SkillsMenuWorld)? = nil
    ) {
        self.menuMode = menuMode
        self.movies = movies
        self.hud = hud
        self.world = world
    }

    /// Holds the layer across both movies, because the level-up pick and the
    /// ring use two.
    lazy var movie = MenuMovieSession(
        movies: movies, hud: hud, label: "skills menu movie"
    ) { [weak self] in self?.world?.renderer }

    /// The level-up movie, drawn over the stats movie while a pick is owed.
    lazy var levelUpMovie = MenuMovieOverlay(movies: movies) { [weak self] in
        self?.world?.renderer
    }

    public var movieLoaded: Bool {
        movie.isLoaded
    }

    public var movieError: String? {
        movie.error
    }

    /// False before a world with progression loads.
    @discardableResult
    public func open() -> Bool {
        guard model == nil, let world, let source = world.skillsMenuSource else { return false }
        source.skillsMenuWillOpen()
        model = SkillsMenuModel(player: source.skillsMenuPlayer, skills: source.skillsMenuSkills)
        loadTrees(source)
        menuMode.inputConsumer = world.menuInputConsumer
        menuMode.present(Self.identifier)
        syncMovie()
        return true
    }

    /// The text goes at once; the sky then plays `CameraOutro` before the menu leaves.
    public func close() {
        guard model != nil, !isClosing else { return }
        stopMovie()
        guard sky.isShown, skyEnabled else {
            finishClose()
            return
        }
        isClosing = true
    }

    /// Off hides the sky at once; on draws it from the next frame.
    public func setSkyEnabled(_ enabled: Bool) {
        skyEnabled = enabled
        if !enabled {
            hideSky()
        }
    }

    func finishClose() {
        model = nil
        isClosing = false
        hideSky()
        menuMode.dismiss(Self.identifier)
    }

    public func route(_ event: MenuInputEvent) {
        guard var model, !isClosing else { return }
        model.message = nil
        let action = model.handle(event)
        self.model = model
        if let action {
            perform(action)
        }
        syncMovie()
    }

    func perform(_ action: SkillsMenuModel.Action) {
        guard let source = world?.skillsMenuSource else { return }
        switch action {
        case let .chooseAttribute(kind):
            report(source.skillsMenuChooseAttribute(kind))
        case let .buyPerk(node, skill):
            report(source.skillsMenuBuyPerk(node: node, forSkill: skill))
        case let .makeLegendary(skill):
            report(source.skillsMenuMakeLegendary(skill))
        case let .showTree(skill):
            model?.setPerks(source.skillsMenuPerks(forSkill: skill))
        case .close:
            close()
            return
        }
        refresh(source)
    }

    /// Reads every value again after a spend, keeping the selection.
    func refresh(_ source: any SkillsMenuSource) {
        guard var model else { return }
        model.refresh(player: source.skillsMenuPlayer, skills: source.skillsMenuSkills)
        if model.page == .perks, let skill = model.selectedSkill {
            model.setPerks(source.skillsMenuPerks(forSkill: skill.index), keepSelection: true)
        }
        self.model = model
        loadTrees(source)
    }

    private func report(_ outcome: SkillsMenuOutcome) {
        switch outcome {
        case let .done(text), let .refused(text):
            Self.logger.info("skills menu: \(text, privacy: .public)")
        }
    }

    public var snapshot: SkillsMenuSnapshot {
        guard let model else {
            return SkillsMenuSnapshot(
                movie: movieSnapshot,
                isSkyEnabled: skyEnabled
            )
        }
        let rows: [String]
        let selected: Int?
        let page: String
        switch model.page {
        case .levelUp:
            page = "Level up (\(model.player.pendingAttributePicks) to choose)"
            rows = SkillsMenuModel.attributes.map(\.rawValue.capitalized)
            selected = model.attributePosition
        case .skills:
            page = "Skills (\(model.player.perkPoints) perk points)"
            rows = model.skills.map(Self.skillRow)
            selected = model.skillPosition
        case .perks:
            page = "\(model.selectedSkill?.name ?? "") perks"
            rows = model.perks.map(Self.perkRow)
            selected = model.perkPosition
        case let .legendary(confirmation):
            page = confirmation.question
            rows = confirmation.options
            selected = confirmation.selectedIndex
        }
        return SkillsMenuSnapshot(
            page: isClosing ? "Closing" : page,
            rows: rows,
            selectedIndex: selected,
            movie: movieSnapshot,
            isSkyEnabled: skyEnabled,
            isLevelUpMovieLoaded: levelUpMovie.isLoaded,
            sky: skyLine
        )
    }

    private var movieSnapshot: TitleMenuMovieSnapshot {
        TitleMenuMovieSnapshot(
            isLoaded: movieLoaded,
            error: movieError,
            state: movie.path.map { ($0 as NSString).lastPathComponent }
        )
    }

    nonisolated static func skillRow(_ skill: SkillsMenuSkill) -> String {
        let legendary = skill.legendaryCount > 0 ? " (legendary x\(skill.legendaryCount))" : ""
        return "\(skill.name) \(Int(skill.level)), \(Int(skill.progress * 100))%\(legendary)"
    }

    nonisolated static func perkRow(_ perk: SkillsMenuPerk) -> String {
        let rank = perk.rankCount > 1 ? " \(perk.ownedRank)/\(perk.rankCount)" : ""
        let state = perk.refusal.map { " - \($0)" } ?? " - available"
        return "\(perk.name)\(rank)\(state)"
    }

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "SkillsMenu"
    )
}
