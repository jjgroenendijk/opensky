public import Foundation
import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAgentControl
import OpenSkyAIPackages
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
public import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `ScriptSessionBindingsAdapter` reads from the session.
@MainActor
public protocol ScriptSessionBindingsHost: AnyObject {
    var effects: any EffectsPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var drawableSize: CGSize { get }
    var menuWorld: any MenuWorldPort { get }
    var movieWorld: any MovieWorldPort { get }
    func quitApplication()
    func quitToMainMenu()
    var renderer: (any RendererPort)? { get }
    var saveGames: any SaveGameWorldPort { get }
    var titleSequence: any TitleSequencePort { get }
}

/// Part of `ScriptWorldAdapter`, over its own narrow host.
public struct ScriptSessionBindingsAdapter {
    public unowned let owner: ScriptWorldAdapter
    public unowned let game: any ScriptSessionBindingsHost
}

extension ScriptSessionBindingsAdapter {
    public func wireGameNatives(bridge: PapyrusWorldStateBridge, provider: WorldDataStores) {
        var hooks = PapyrusGameNatives()
        wireSaveAndScreen(&hooks)
        owner.playerBindings.wirePlayerRules(&hooks)
        owner.referenceBindings.wireReferenceRules(&hooks, provider: provider)
        owner.soundBindings.wireSounds(&hooks)
        owner.nodeBindings.wirePaths(&hooks)
        hooks.playBink = { [weak movies = game.movieWorld] request, token in
            movies?.playBink(request, waitToken: token) ?? false
        }
        hooks.nodeTransform = owner.modelNodes.flatMap { nodes in
            { [weak owner] key, name, then in
                owner?.nodeBindings
                    .nodeTransform(of: key, named: name, nodes: nodes, then: then) ?? .missing
            }
        }
        bridge.gameNatives = hooks
    }

    private func wireSaveAndScreen(_ hooks: inout PapyrusGameNatives) {
        hooks.requestSave = { [weak game] autosave in
            game?.saveGames.requestSave(autosave: autosave) ?? false
        }
        hooks.quitToMainMenu = { [weak game] in game?.quitToMainMenu() }
        hooks.quitGame = { [weak game] in game?.quitApplication() }
        hooks.fade = { [weak game] fade in
            game?.gameSession?.imageSpace.screenFade.start(
                fadingOut: fade.fadingOut, black: fade.black,
                delay: fade.secondsBeforeFade, duration: fade.duration
            )
        }
        hooks.showTitleSequenceMenu = { [weak game] shown in game?.titleSequence.show(shown) }
        hooks.startTitleSequence = { [weak game] name in _ = game?.titleSequence.start(name) }
        hooks.screenBlood = { [weak game] count in game?.effects.splatterScreen(count: count) }
        hooks.clearTempEffects = { [weak game] in game?.effects.clearTemporaryBlood() }
        hooks.takeScreenshot = { [weak game] name in
            guard let game, let renderer = game.renderer else { return false }
            let size = game.drawableSize
            return Self.writeScreenshot(named: name, renderer: renderer, size: size)
        }
        hooks.toggleCollisions = { [weak game] in
            guard let session = game?.gameSession else { return }
            session.setMovementMode(session.movementMode == .fly ? .walk : .fly)
        }
        hooks.centerOnCell = { [weak game] cell in
            game?.menuWorld.teleportPlayer(.cell(cell), openingRaceMenu: false)
            return game != nil
        }
        hooks.showFirstPersonGeometry = { [weak game] shown in
            game?.gameSession?.firstPersonArmsEnabled = shown
        }
    }

    /// The game writes into its install folder, which OpenSky keeps read-only, so the
    /// capture goes to the user's pictures instead.
    private static func writeScreenshot(
        named name: String, renderer: any RendererPort, size: CGSize
    ) -> Bool {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard
            width > 0, height > 0,
            let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)
                .first,
            let texture = try? renderer.renderOffscreen(width: width, height: height)
        else { return false }
        let file = (name.isEmpty ? "ScreenShot" : name) + ".png"
        let url = pictures.appending(path: "OpenSky").appending(path: file)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        return (try? FrameScreenshot.write(texture: texture, to: url)) != nil
    }
}
