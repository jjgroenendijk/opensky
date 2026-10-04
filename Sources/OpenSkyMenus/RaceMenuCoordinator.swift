// Opens the race menu on the menu stack, routes keys and typed text to
// `RaceMenuModel`, and hands the result to the world. The vanilla
// `racesex_menu.swf` movie is not driven yet; see docs/engine/race-menu.md.

import Foundation
import OpenSkyActorsInterface

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
    var menuInputConsumer: (any MenuInputConsumer)? { get }
}

nonisolated public struct RaceMenuSnapshot: Equatable, Sendable {
    public let isOpen: Bool
    public let isLimited: Bool
    public let isEditingName: Bool
    public let rows: [String]
    public let selectedIndex: Int
    public let lastResult: String?

    public init(
        isOpen: Bool, isLimited: Bool, isEditingName: Bool, rows: [String], selectedIndex: Int,
        lastResult: String?
    ) {
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
}

public final class RaceMenuCoordinator {
    public static let identifier: MenuIdentifier = "RaceSex Menu"

    public private(set) var model: RaceMenuModel?
    public private(set) var isEditingName = false
    public private(set) var lastResult: String?
    private var typedName = ""
    private let menuMode: MenuModeController
    private weak var world: (any RaceMenuWorld)?

    public init(menuMode: MenuModeController) {
        self.menuMode = menuMode
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
        return true
    }

    public func route(_ event: MenuInputEvent) {
        guard var model else { return }
        if isEditingName {
            switch event {
            case .button(.accept): finishName(apply: true)
            case .button(.cancel): finishName(apply: false)
            default: break
            }
            return
        }
        let action = model.handle(event)
        self.model = model
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
            lastResult: lastResult
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
}
