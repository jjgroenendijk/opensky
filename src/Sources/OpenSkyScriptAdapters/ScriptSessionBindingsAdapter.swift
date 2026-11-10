public import Foundation
import OpenSkyActorPresentation
import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `ScriptSessionBindingsAdapter` reads from the session.
@MainActor
public protocol ScriptSessionBindingsHost: AnyObject, SendableMetatype {
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
    public let game: any ScriptSessionBindingsHost
    public let state: ScriptPartState
    public let playerBindings: ScriptPlayerBindingsAdapter
    public let referenceBindings: ScriptReferenceBindingsAdapter
    public let soundBindings: ScriptSoundBindingsAdapter
    public let nodeBindings: ScriptNodeBindingsAdapter
}

extension ScriptSessionBindingsAdapter {
    /// The game writes into its install folder, which OpenSky keeps read-only, so the
    /// capture goes to the user's pictures instead.
    static func writeScreenshot(
        named name: String, renderer: any RendererPort, size: CGSize
    ) -> Bool {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard
            width > 0, height > 0,
            let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)
                .first,
            let texture = attempt({ try renderer.renderOffscreen(width: width, height: height) })
        else { return false }
        let file = (name.isEmpty ? "ScreenShot" : name) + ".png"
        let url = pictures.appending(path: "OpenSky").appending(path: file)
        let folder = url.deletingLastPathComponent()
        let files = FileManager.default
        attempt { try files.createDirectory(at: folder, withIntermediateDirectories: true) }
        return attempt { try FrameScreenshot.write(texture: texture, to: url) } != nil
    }
}
