public import AppKit
import Foundation
import MetalKit
import OpenSkyActorPresentation
import OpenSkyActors
public import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyDialogue
import OpenSkyEffects
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyLoading
import OpenSkyMagic
public import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyObjectAnimation
import OpenSkyPerception
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkyScripting
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `AgentInputAdapter` reads from the session.
@MainActor
public protocol AgentInputHost: AnyObject {
    var cameraInput: any CameraInputStatePort { get }
    var viewBounds: CGRect { get }
    var inventoryMenu: any InventoryMenuPort { get }
    var journalMenu: any JournalMenuPort { get }
    var menuMode: any MenuModePort { get }
    var messages: any MessageCoordinatorPort { get }
    var playerControlLocks: PlayerControlLocks { get }
    var raceMenu: any RaceMenuPort { get }
    func runCommand(_ action: GameInputAction)
    func showControlRefusal(_ refusal: PlayerControlRefusal)
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentInputAdapter {
    public unowned let owner: AgentWorldAdapter
    public let game: any AgentInputHost
}

extension AgentInputAdapter {
    public var dispatcher: GameInputDispatcher {
        GameInputDispatcher(
            input: game.cameraInput,
            menuMode: game.menuMode,
            openJournal: { [weak game] in game?.journalMenu.open() },
            openInventory: { [weak game] in game?.inventoryMenu.open() },
            onCommand: { [weak game] in game?.runCommand($0) },
            locks: game.playerControlLocks,
            onRefused: { [weak game] in game?.showControlRefusal($0) }
        )
    }

    public func applyInput(_ name: String, phase: AgentInputPhase) throws(AgentFailure) -> Bool {
        guard let action = GameInputAction(rawValue: name) else {
            let known = GameInputAction.allCases.map(\.rawValue).joined(separator: ", ")
            throw AgentFailure(.invalidArgument, "unknown action '\(name)'; known: \(known)")
        }
        // As from the keyboard, so a help message waiting for the action ends.
        if
            phase != .release, !game.menuMode.isMenuMode,
            let event = action.helpEvent
        {
            game.messages.noteInputEvent(event)
        }
        let outcome = dispatcher.apply(action, phase == .release ? .release : .press)
        if outcome == .noMenu {
            throw AgentFailure(.invalidArgument, "'\(name)' needs an open menu")
        }
        // A press of activate is a tap; only `input hold` keeps it down.
        if phase == .press, action == .activate, !game.menuMode.isMenuMode {
            _ = dispatcher.apply(action, .release)
        }
        return phase == .hold ? action.sendsRelease : action.isHeld
    }

    public func look(yawDegrees: Float, pitchDegrees: Float) throws(AgentFailure) {
        guard !game.menuMode.isMenuMode else {
            throw AgentFailure(.invalidArgument, "a menu owns input; close it first")
        }
        if yawDegrees != 0 || pitchDegrees != 0 {
            game.messages.noteInputEvent(GameInputAction.lookHelpEvent)
        }
        let pointsPerDegree = MatrixMath.radians(fromDegrees: 1) / FreeFlyCamera.lookSensitivity
        game.cameraInput.addLook(
            right: yawDegrees * pointsPerDegree,
            up: pitchDegrees * pointsPerDegree
        )
    }

    public func selectMenuRow(label: String) throws(AgentFailure) -> AgentJSON {
        guard let start = owner.menuReadout.menuRows() else {
            throw AgentFailure(.notFound, "no open menu has a row list")
        }
        guard let target = AgentMenuReadoutAdapter.rowIndex(of: label, in: start.rows) else {
            throw AgentFailure(.notFound, "no row '\(label)' in \(start.menu)")
        }
        var current = start.selected
        while current != target {
            let action: GameInputAction = target > current ? .menuDown : .menuUp
            dispatcher.apply(action, .press)
            dispatcher.apply(action, .release)
            guard let next = owner.menuReadout.menuRows()?.selected, next != current else { break }
            current = next
        }
        guard current == target else {
            throw AgentFailure(.failed, "the selection stopped at row \(current), not \(target)")
        }
        return [
            "menu": .string(start.menu),
            "index": .init(target),
            "label": .string(start.rows[target])
        ]
    }

    /// The same pointer events the view sends for a real cursor.
    public func pointMenu(x: Float, y: Float, click: Bool) throws(AgentFailure) -> AgentJSON {
        guard game.menuMode.isMenuMode else {
            throw AgentFailure(.invalidArgument, "no menu is open")
        }
        let bounds = game.viewBounds
        let size = SIMD2(Float(bounds.width), Float(bounds.height))
        let location = SIMD2(x, y) * size
        let phases: [MenuPointerEvent.Phase] = click ? [.moved, .pressed, .released] : [.moved]
        for phase in phases {
            game.menuMode.routeMenuPointer(MenuPointerEvent(
                phase,
                location: location,
                viewSize: size
            ))
        }
        return ["x": .init(x), "y": .init(y), "clicked": .bool(click)]
    }

    public func typeText(_ text: String) throws(AgentFailure) -> AgentJSON {
        guard game.raceMenu.type(text) else {
            throw AgentFailure(.notFound, "no open menu takes text now")
        }
        return ["typed": .string(text)]
    }
}
