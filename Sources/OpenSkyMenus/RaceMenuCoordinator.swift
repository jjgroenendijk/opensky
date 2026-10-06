// Opens the race menu on the menu stack, routes keys and typed text to
// `RaceMenuModel`, and hands the result to the world. It shows the vanilla
// `racesex_menu.swf` movie when it loads; see docs/engine/race-menu.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyRendering

/// What the race menu reads from and writes to the running game.
public protocol RaceMenuWorld: AnyObject {
    /// The player's identity now: the saved one, else the `Player` record's.
    var playerIdentity: PlayerIdentityState? { get }
    /// The vanilla `Player` record's identity, before any change.
    var recordIdentity: PlayerIdentityState? { get }
    var playableRaces: [RaceChoice] { get }
    /// Stores the identity and rebuilds the player's body.
    func applyPlayerIdentity(_ identity: PlayerIdentityState)
    /// Fires `OnRaceSwitchComplete` on the player's scripts.
    func raceMenuClosed()
    /// The race's preset faces (`RPRM` or `RPRF`), each read from its NPC_ record.
    func racePresets(race: FormID, isFemale: Bool) -> [RacePreset]
    var menuInputConsumer: (any MenuInputConsumer)? { get }
    var renderer: Renderer? { get }
}

/// One preset face a race offers in the race menu.
nonisolated public struct RacePreset: Equatable, Sendable {
    public let name: String
    public let face: PlayerFace

    public init(name: String, face: PlayerFace) {
        self.name = name
        self.face = face
    }
}

nonisolated public struct RaceMenuSnapshot: Equatable, Sendable {
    public let isOpen: Bool
    public let isLimited: Bool
    public let isEditingName: Bool
    public let rows: [String]
    public let selectedIndex: Int
    public let lastResult: String?
    /// The player's face now: weight, the slider values that are not 0, parts, and tints.
    public let face: [String]
    public let movie: TitleMenuMovieSnapshot

    public init(
        isOpen: Bool, isLimited: Bool, isEditingName: Bool, rows: [String], selectedIndex: Int,
        lastResult: String?, face: [String] = [], movie: TitleMenuMovieSnapshot = .init()
    ) {
        self.face = face
        self.movie = movie
        self.isOpen = isOpen
        self.isLimited = isLimited
        self.isEditingName = isEditingName
        self.rows = rows
        self.selectedIndex = selectedIndex
        self.lastResult = lastResult
    }
}

/// The sidebar's view of the race menu.
public protocol RaceMenuControlProviding: AnyObject {
    var raceMenuSnapshot: RaceMenuSnapshot { get }
    func openRaceMenu(limited: Bool)
    func sendRaceMenuInput(_ event: MenuInputEvent)
    func setRaceMenuName(_ name: String)
    func resetPlayerIdentity()
    func applyRacePreset(offset: Int)
    func setRaceMenuMovieEnabled(_ enabled: Bool)
}

public final class RaceMenuCoordinator {
    public static let identifier: MenuIdentifier = "RaceSex Menu"

    public internal(set) var model: RaceMenuModel?
    public private(set) var isEditingName = false
    public internal(set) var lastResult: String?
    /// The movie is the menu the player sees; the engine rows stay the fallback.
    public private(set) var movieEnabled = true
    public internal(set) var movieLoaded = false
    public internal(set) var movieError: String?
    /// Bumped by each open and close, so a movie decoded late opens only the newest.
    var movieRequest = 0
    /// Movie calls made during input, applied once the movie returns.
    var pendingMovieRequests: [RaceMenuMovieBridge.Request] = []
    var framePacer = MenuMovieFramePacer()
    /// True from the HUD's suspension until it is started again.
    var holdsLayer = false
    let movies: SWFMovieSource?
    let hud: HUDCoordinator?
    private var typedName = ""
    /// The preset the sidebar applied last, so the next press moves on from it.
    private var presetIndex: Int?
    private let menuMode: MenuModeController
    private(set) weak var world: (any RaceMenuWorld)?

    public init(
        menuMode: MenuModeController, movies: SWFMovieSource? = nil, hud: HUDCoordinator? = nil
    ) {
        self.menuMode = menuMode
        self.movies = movies
        self.hud = hud
    }

    public func attach(world: any RaceMenuWorld) {
        self.world = world
    }

    public var isOpen: Bool {
        model != nil
    }

    /// False when there is no identity to edit, such as before a world loads.
    @discardableResult
    public func open(limited: Bool) -> Bool {
        guard model == nil, let world, let identity = world.playerIdentity else { return false }
        model = RaceMenuModel(identity: identity, races: world.playableRaces, limited: limited)
        isEditingName = false
        menuMode.inputConsumer = world.menuInputConsumer
        menuMode.present(Self.identifier)
        if movieEnabled {
            startMovie()
        }
        return true
    }

    public func setMovieEnabled(_ enabled: Bool) {
        guard enabled != movieEnabled else { return }
        movieEnabled = enabled
        guard isOpen else { return }
        if enabled {
            startMovie()
        } else {
            stopMovie()
        }
    }

    public func route(_ event: MenuInputEvent) {
        if movieLoaded, let renderer = world?.renderer {
            routeMovie(event, renderer: renderer)
            return
        }
        guard var model else { return }
        if isEditingName {
            switch event {
            case .button(.accept): finishName(apply: true)
            case .button(.cancel): finishName(apply: false)
            default: break
            }
            return
        }
        let before = model.identity
        let action = model.handle(event)
        self.model = model
        // A slider shows on the head at once, not only when the menu closes.
        if model.identity != before, action != .done {
            world?.applyPlayerIdentity(model.identity)
        }
        switch action {
        case .done: close()
        case .editName: startName()
        case nil: break
        }
    }

    /// Typed characters while the name row is being edited. False when the
    /// menu does not take text now, so the key goes elsewhere.
    public func type(_ text: String) -> Bool {
        guard isEditingName else { return false }
        for character in text {
            if character == "\u{7F}" || character == "\u{8}" {
                if !typedName.isEmpty {
                    typedName.removeLast()
                }
            } else if !character.isNewline, typedName.count < PlayerIdentityState.nameLimit {
                typedName.append(character)
            }
        }
        return true
    }

    public func setName(_ name: String) {
        model?.setName(name)
    }

    private func startName() {
        guard let model, !model.isLimited else { return }
        typedName = model.identity.name
        isEditingName = true
    }

    private func finishName(apply: Bool) {
        if apply {
            model?.setName(typedName)
        }
        isEditingName = false
    }

    public func close() {
        guard let model else { return }
        self.model = nil
        stopMovie()
        isEditingName = false
        menuMode.dismiss(Self.identifier)
        world?.applyPlayerIdentity(model.identity)
        world?.raceMenuClosed()
        let race = model.value(.race)
        lastResult = "\(model.identity.name), \(race), \(model.value(.sex))"
    }

    /// Puts the player back to the `Player` record; only while the menu is closed.
    public func resetToRecord() {
        guard !isOpen, let world, let identity = world.recordIdentity else { return }
        world.applyPlayerIdentity(identity)
        lastResult = "Reset to the Player record"
    }

    /// Puts the next or previous preset face of the player's race on the player;
    /// only while the menu is closed.
    public func applyPreset(offset: Int) {
        guard !isOpen, let world, var identity = world.playerIdentity else { return }
        let presets = world.racePresets(race: identity.race, isFemale: identity.isFemale)
        guard !presets.isEmpty else {
            lastResult = "No presets for this race"
            return
        }
        let index = presetIndex.map {
            ($0 + offset % presets.count + presets.count) % presets.count
        } ?? (offset < 0 ? presets.count - 1 : 0)
        presetIndex = index
        identity.face = presets[index].face
        world.applyPlayerIdentity(identity)
        lastResult = "Preset \(index + 1) of \(presets.count): \(presets[index].name)"
    }

    public var snapshot: RaceMenuSnapshot {
        RaceMenuSnapshot(
            isOpen: isOpen,
            isLimited: model?.isLimited ?? false,
            isEditingName: isEditingName,
            rows: model.map { model in
                model.rows.map { row in
                    let value = isEditingName && row == .name ? typedName + "_" : model.value(row)
                    return "\(model.label(row)): \(value)"
                }
            } ?? [],
            selectedIndex: model?.selectedIndex ?? 0,
            lastResult: lastResult,
            face: (model?.identity ?? world?.playerIdentity).map { Self.faceLines($0.face) } ?? [],
            movie: TitleMenuMovieSnapshot(
                isEnabled: movieEnabled, isLoaded: movieLoaded, error: movieError
            )
        )
    }
}

/// Lets the app's provider object stand in for its `RaceMenuCoordinator`.
public protocol RaceMenuControlForwarding: RaceMenuControlProviding {
    var raceMenu: RaceMenuCoordinator { get }
}

extension RaceMenuControlForwarding {
    public var raceMenuSnapshot: RaceMenuSnapshot {
        raceMenu.snapshot
    }

    public func resetPlayerIdentity() {
        raceMenu.resetToRecord()
    }

    public func openRaceMenu(limited: Bool) {
        raceMenu.open(limited: limited)
    }

    public func sendRaceMenuInput(_ event: MenuInputEvent) {
        raceMenu.route(event)
    }

    public func setRaceMenuName(_ name: String) {
        raceMenu.setName(name)
    }

    public func applyRacePreset(offset: Int) {
        raceMenu.applyPreset(offset: offset)
    }

    public func setRaceMenuMovieEnabled(_ enabled: Bool) {
        raceMenu.setMovieEnabled(enabled)
    }
}

extension RaceMenuCoordinator {
    nonisolated static func faceLines(_ face: PlayerFace) -> [String] {
        let labels = RaceMenuModel.sliderLabels + ["Vampire"]
        let sliders = face.morphs.enumerated().filter { $0.element != 0 }.map { index, value in
            let label = labels.indices.contains(index) ? labels[index] : "Slider \(index)"
            return String(format: "%@ %.2f", label, value)
        }
        let tints = face.tints.map { tint in
            String(
                format: "mask %d rgb %d %d %d at %.2f", tint.maskIndex, tint.color.x, tint.color.y,
                tint.color.z, tint.strength
            )
        }
        return [
            String(format: "Weight: %.0f", face.weight),
            "Sliders: " + (sliders.isEmpty ? "all 0" : sliders.joined(separator: ", ")),
            "Parts: " + face.parts.map(String.init).joined(separator: " "),
            "Tints: " + (tints.isEmpty ? "none" : tints.joined(separator: "; "))
        ]
    }
}
