import Foundation
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyCombatInterface
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLoading
import OpenSkyMenusInterface
import OpenSkyObjectAnimation
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySaveInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `AgentRenderAdapter` reads from the session.
@MainActor
public protocol AgentRenderHost: AnyObject, SendableMetatype {
    var audio: any AudioPort { get }
    var combat: any CombatPort { get }
    var effects: any EffectsPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var loadingScreens: any LoadingScreenPort { get }
    var movies: any MoviePlayerPort { get }
    var playerSettings: any PlayerSettingsPort { get }
    var renderControls: any WorldRenderControlsPort { get }
    var renderer: (any RendererPort)? { get }
    var scripts: any ScriptPort { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentRenderAdapter {
    let hub: AgentHub
    public let game: any AgentRenderHost
}

extension AgentRenderAdapter {
    public func screenFadeState() -> AgentJSON {
        guard let fade = game.gameSession?.imageSpace.screenFade else { return .null }
        return [
            "colour": .string(fade.colour == .zero ? "black" : "white"),
            "cover": .init(fade.cover), "running": .bool(fade.isRunning)
        ]
    }

    /// Overlays, then the render-debug layers, such as `distantlod`.
    static let overlayNames = ["navmesh", "path", "detection", "hud", "ui"]
        + RenderLayer.ordered.map { $0.identifierFragment.lowercased() }

    /// Applies `pairs` over a copy of the saved settings, so nothing is written to disk.
    private func applySettings(_ pairs: [String]) throws(AgentFailure) -> AgentJSON {
        guard let session = game.gameSession else { throw hub.notReady() }
        let saved = game.playerSettings.store
        var overrides: [PlayerSettingID: Double] = [:]
        for pair in pairs {
            let parsed: (id: String, value: Double)
            do {
                parsed = try BenchmarkRequest.parseSetting(pair, catalog: saved.catalog)
            } catch {
                throw AgentFailure(.invalidArgument, String(describing: error))
            }
            let id = PlayerSettingID(parsed.id)
            guard let value = saved.catalog.definition(id)?.clamp(parsed.value) else {
                throw AgentFailure(.invalidArgument, "value out of range: \(pair)")
            }
            overrides[id] = value
        }
        let store = PlayerSettingsStore(copying: saved, overrides: overrides)
        session.applyGraphicsSettings(store)
        game.effects.applyGraphicsSettings(store)
        let applied = overrides.map { ($0.key.rawValue, AgentJSON.number($0.value)) }
        return ["settings": .object(Dictionary(uniqueKeysWithValues: applied))]
    }

    private func setSound(_ on: Bool) -> AgentJSON {
        game.audio.outputMuted = !on
        return ["muted": .bool(game.audio.outputMuted)]
    }

    public func renderDebug(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
        switch command {
        case let .overlay(name, enabled): try setOverlay(name, enabled: enabled)
        case let .channel(name): try setChannel(name)
        case let .shadows(name): try setShadowQuality(name)
        case let .fade(request): try fade(request)
        case let .cartMode(enabled): try setCartMode(enabled)
        case let .playBink(file, interruptible):
            try playBink(MovieRequest(fileName: file, interruptible: interruptible))
        case .skipBink:
            [
                "skipped": .bool(game.movies.skip(force: true)),
                "bink": screens.binkState
            ]
        case let .titles(step): try driveTitles(step)
        case let .loadScreen(editorID): try forceLoadScreen(editorID)
        case let .sound(on): setSound(on)
        case let .settings(pairs): try applySettings(pairs)
        default: throw AgentFailure(.invalidArgument, "not a render debug command")
        }
    }

    public func forceWeather(_ editorID: String?) throws(AgentFailure) -> AgentJSON {
        guard game.gameSession?.weather != nil else {
            throw AgentFailure(.notReady, "no weather data is loaded")
        }
        guard let editorID else {
            game.renderControls.forceWeather(named: nil, transition: .instant)
            return ["forced": .null]
        }
        let names = game.renderControls.selectableWeatherNames
        guard let match = names.first(where: { $0.lowercased() == editorID.lowercased() }) else {
            throw AgentFailure(.notFound, "no selectable weather '\(editorID)'")
        }
        // A paused game counts no game hours, so a timed fade would never finish.
        game.renderControls.forceWeather(named: match, transition: .instant)
        return ["forced": .string(match)]
    }

    private func setOverlay(_ name: String, enabled: Bool) throws(AgentFailure) -> AgentJSON {
        guard let renderer = game.renderer else { throw hub.notReady() }
        switch name.lowercased() {
        case "navmesh": renderer.navmeshOverlayEnabled = enabled
        case "path": renderer.pathOverlayEnabled = enabled
        case "detection": renderer.detectionOverlayEnabled = enabled
        case "hud": renderer.swfEnabled = enabled
        case "ui": renderer.uiEnabled = enabled
        default:
            guard let layer = Self.layer(named: name.lowercased()) else {
                let known = Self.overlayNames.joined(separator: ", ")
                throw AgentFailure(.invalidArgument, "unknown overlay '\(name)'; known: \(known)")
            }
            let layers = renderer.renderDebug.layers
            renderer.renderDebug.layers = enabled ? layers.union(layer) : layers.subtracting(layer)
        }
        return ["overlay": .string(name.lowercased()), "on": .bool(enabled)]
    }

    private func setChannel(_ name: String) throws(AgentFailure) -> AgentJSON {
        guard let renderer = game.renderer else { throw hub.notReady() }
        let modes = RenderDebugMode.allCases
        guard let mode = modes.first(where: { "\($0)".lowercased() == name.lowercased() }) else {
            let known = modes.map { "\($0)".lowercased() }.joined(separator: ", ")
            throw AgentFailure(.invalidArgument, "unknown channel '\(name)'; known: \(known)")
        }
        renderer.renderDebug.mode = mode
        return ["channel": .string("\(mode)".lowercased())]
    }

    /// Goes through the script hook, so the reply shows what a script's fade does.
    private func fade(_ request: AgentFadeRequest) throws(AgentFailure) -> AgentJSON {
        guard let fade = game.scripts.bridge?.gameNatives.fade else { throw hub.notReady() }
        fade(PapyrusFade(
            fadingOut: request.fadingOut, black: request.black,
            secondsBeforeFade: request.delay, duration: request.duration
        ))
        return ["screenFade": screenFadeState()]
    }

    private func playBink(_ request: MovieRequest) throws(AgentFailure) -> AgentJSON {
        guard game.movies.play(request, onEnd: { _ in }) else {
            throw AgentFailure(.invalidArgument, "a movie plays already, or no game files")
        }
        return ["bink": screens.binkState]
    }

    /// Goes through the script hooks, as `fade` does.
    private func driveTitles(_ step: String) throws(AgentFailure) -> AgentJSON {
        guard let natives = game.scripts.bridge?.gameNatives else { throw hub.notReady() }
        switch step.lowercased() {
        case "show": natives.showTitleSequenceMenu?(true)
        case "hide": natives.showTitleSequenceMenu?(false)
        default:
            guard TitleSequenceClip.path(for: step) != nil else {
                throw AgentFailure(.invalidArgument, "step must be show, hide, or Sequence1 to 4")
            }
            natives.startTitleSequence?(step)
        }
        return ["titles": screens.titlesState]
    }

    /// The screen holds until a call with no ID, which starts its fade.
    private func forceLoadScreen(_ editorID: String?) throws(AgentFailure) -> AgentJSON {
        let now = hub.now().timeIntervalSinceReferenceDate
        guard let editorID else {
            game.loadingScreens.releaseForced(at: now)
            return ["loading": screens.loadingState]
        }
        guard game.loadingScreens.force(editorID: editorID, at: now) else {
            throw AgentFailure(.notFound, "no loading screen \(editorID)")
        }
        return ["loading": screens.loadingState]
    }

    /// Goes through the script hook, as `fade` does.
    private func setCartMode(_ enabled: Bool) throws(AgentFailure) -> AgentJSON {
        guard let menus = game.scripts.bridge?.menus else { throw hub.notReady() }
        menus.setHUDCartMode(enabled)
        return ["hud": screens.hudState]
    }

    private func setShadowQuality(_ name: String) throws(AgentFailure) -> AgentJSON {
        guard let renderer = game.renderer else { throw hub.notReady() }
        guard let quality = ShadowQuality(rawValue: name.lowercased()) else {
            let known = ShadowQuality.allCases.map(\.rawValue).joined(separator: ", ")
            throw AgentFailure(
                .invalidArgument,
                "unknown shadow quality '\(name)'; known: \(known)"
            )
        }
        renderer.shadowQuality = quality
        return [
            "shadows": .string(quality.rawValue),
            "shadowLights": .number(Double(renderer.pointShadowLightCount))
        ]
    }

    private static func layer(named name: String) -> RenderLayer? {
        RenderLayer.ordered.first { $0.identifierFragment.lowercased() == name }
    }

    public func lightingState() -> AgentJSON {
        stateReads.lightingState()
    }

    public func postEffectState() -> AgentJSON {
        stateReads.postEffectState()
    }

    public func projectileVisualState() -> AgentJSON {
        stateReads.projectileVisualState()
    }

    public func soundMixState() -> AgentJSON {
        stateReads.soundMixState()
    }

    func skinDecalBones(of actor: ReferenceKey) -> [String] {
        stateReads.skinDecalBones(of: actor)
    }

    public func treeWindState() -> AgentJSON {
        stateReads.treeWindState()
    }

    public func waterFlowState() -> AgentJSON {
        stateReads.waterFlowState()
    }

    public func precipitationState() -> AgentJSON {
        stateReads.precipitationState()
    }

    func healthCueState() -> AgentJSON {
        stateReads.healthCueState()
    }
}

extension AgentRenderAdapter {
    private var stateReads: AgentRenderStateReads {
        AgentRenderStateReads(game: game)
    }

    private var screens: AgentScreensAdapter {
        AgentScreensAdapter(hub: hub, game: hub.hosts)
    }
}
