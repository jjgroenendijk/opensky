import Foundation
import OpenSkyActors
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyObjectAnimation
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuests
import OpenSkyQuestsInterface
public import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySaveInterface
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `AgentScreensAdapter` reads from the session.
@MainActor
public protocol AgentScreensHost: AnyObject {
    var hud: any HUDPort { get }
    var loadingScreens: any LoadingScreenPort { get }
    var loadingWorld: any LoadingScreenWorldPort { get }
    var mapMenu: any MapMenuPort { get }
    var mapWorld: any MapWorldPort { get }
    var menuRouter: any MenuRouterPort { get }
    var movies: any MoviePlayerPort { get }
    var renderer: (any RendererPort)? { get }
    var titleSequence: any TitleSequencePort { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentScreensAdapter {
    public unowned let owner: AgentWorldAdapter
    public let game: any AgentScreensHost
}

extension AgentScreensAdapter {
    /// The opening titles: shown, loaded, and the clip asked for last.
    public var titlesState: AgentJSON {
        let titles = game.titleSequence
        return [
            "shown": .bool(titles.isShown), "loaded": .bool(titles.isLoaded),
            "sequence": .init(titles.lastSequence)
        ]
    }

    /// The Bink movie on screen, and how the last one ended.
    public var binkState: AgentJSON {
        let readout = game.movies.readout
        let outcome: AgentJSON = switch readout.lastOutcome {
        case .finished: "finished"
        case .skipped: "skipped"
        case let .failed(reason): .string("failed: \(reason)")
        case nil: .null
        }
        let frame: AgentJSON = readout.frame.map { AgentJSON($0) } ?? .null
        let frameCount: AgentJSON = readout.frameCount.map { AgentJSON($0) } ?? .null
        return .object([
            "file": AgentJSON(readout.fileName), "loading": .bool(readout.loading),
            "frame": frame, "frameCount": frameCount,
            "interruptible": .bool(readout.interruptible), "lastOutcome": outcome
        ])
    }

    /// The menu movie's focused clip, its frame label, controllers, and button-art platform.
    public var movieFocusState: AgentJSON {
        guard let runtime = game.renderer?.swfRuntime else { return .null }
        let focus = runtime.focusTarget
        return [
            "focus": .init(focus?.targetPath),
            "focusLabel": .init(focus.flatMap(runtime.currentFrameLabel(of:))),
            "controllers": .init(runtime.controllerCount),
            "platform": .number(runtime.inputPlatform)
        ]
    }

    /// `debug gamepad`: the reported gamepads change at once; presses arrive next frame.
    public func driveGamepad(count: Int?, press: [String]) throws(AgentFailure) -> AgentJSON {
        let gamepads = game.menuRouter.gamepads
        var buttons: Set<GamepadButton> = []
        for name in press {
            guard let button = Self.gamepadButtons[name] else {
                throw AgentFailure(.invalidArgument, "unknown gamepad button: \(name)")
            }
            buttons.insert(button)
        }
        if let count {
            gamepads.simulatedCount = count
        }
        gamepads.simulatedPress.formUnion(buttons)
        return ["simulated": .init(gamepads.simulatedCount), "pressed": .init(buttons.count)]
    }

    private static let gamepadButtons: [String: GamepadButton] = [
        "a": .a, "b": .b, "x": .x, "y": .y,
        "up": .dpadUp, "down": .dpadDown, "left": .dpadLeft, "right": .dpadRight
    ]

    /// The loading screen: whether it covers, which screen, and its movie.
    public var loadingState: AgentJSON {
        let loading = game.loadingScreens
        let session = loading.session
        return [
            "covering": .bool(loading.isCovering),
            "waiting": .bool(loading.isWaitingForDestination),
            "screen": .init(session?.screen?.record.editorID),
            "cameraPath": .init(session?.screen?.record.cameraPath),
            "turn": .number(Double(session?.turnDegrees ?? 0)),
            "movieLoaded": .bool(game.loadingWorld.isMovieLoaded),
            "shown": .init(loading.shownCount)
        ]
    }

    /// The map's mode, selection, last result, and the custom marker on the map and compass.
    public var mapState: AgentJSON {
        let snapshot = game.mapMenu.snapshot
        let compass = game.hud.playerSetMarker.map { AgentJSON.array([.init($0.x), .init($0.y)]) }
        return [
            "mode": .init(game.mapMenu.mode?.rawValue), "selected": .init(snapshot.selected),
            "lastResult": .init(snapshot.lastResult), "playerMarker": .init(snapshot.playerMarker),
            "compassPlayerMarker": compass ?? .null,
            "focus": game.mapMenu.camera.map { .array([.init($0.focus.x), .init($0.focus.y)]) }
                ?? .null
        ]
    }

    public var hudState: AgentJSON {
        [
            "loaded": .bool(game.hud.isLoaded), "cartMode": .bool(game.hud.isCartMode),
            "modes": .array(game.hud.shownModes.map { .string($0.rawValue) }),
            "activatePrompt": .init(game.hud.effectivePrompt),
            "activateLocked": .bool(game.hud.isActivateLocked),
            "notifications": .array(game.hud.shownNotifications.map { .string($0) }),
            "bigNotices": .array(game.hud.shownBigNotices.map { notice in
                .string("\(notice.title) | \(notice.status)")
            })
        ]
    }

    /// The marker is found by its map name; the map's refusals do not apply.
    public func fastTravel(to name: String) throws(AgentFailure) -> AgentJSON {
        let wanted = name.lowercased()
        guard let site = game.mapWorld.mapMarkerSites().first(where: {
            $0.name.lowercased() == wanted
        }) else {
            throw AgentFailure(.notFound, "no map marker named \(name)")
        }
        guard game.mapWorld.travel(to: site) else { throw owner.notReady() }
        return ["marker": .string(site.name), "loading": loadingState]
    }
}
