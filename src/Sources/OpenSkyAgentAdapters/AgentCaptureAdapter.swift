public import Foundation
import Metal
import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLoading
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyObjectAnimation
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `AgentCaptureAdapter` reads from the session.
@MainActor
public protocol AgentCaptureHost: AnyObject, SendableMetatype {
    var gameSession: (any GameSessionPort)? { get }
    var drawableSize: CGSize { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentCaptureAdapter {
    public let hub: AgentHub
    public let game: any AgentCaptureHost
}

extension AgentCaptureAdapter {
    public func captureScreenshot(_ request: AgentScreenshotRequest) throws(AgentFailure)
        -> AgentHandling
    {
        guard let gameSession = game.gameSession else {
            throw hub.notReady()
        }
        if request.offscreen {
            return try .done(.success(captureOffscreen(
                request,
                gameSession: gameSession,
                drawableSize: game.drawableSize
            )))
        }
        let renderer = gameSession.renderer
        renderer.requestWindowCapture()
        var deadline: Double?
        return .waiting(AgentWait { [weak renderer] now in
            guard let renderer else { return .done(.failure(Self.closed)) }
            let limit = deadline ?? now + Self.windowCaptureSeconds
            deadline = limit
            guard let texture = renderer.takeWindowCapture() else {
                return now < limit ? .wait : .done(.failure(Self.noWindowFrame))
            }
            return .done(Result { () throws(AgentFailure) in
                try Self.write(texture, to: request.path)
                return Self.reply(request, texture: texture, source: "window")
            })
        })
    }

    private static let windowCaptureSeconds = 2.0
    private static let closed = AgentFailure(.notReady, "the game closed")
    private static let noWindowFrame = AgentFailure(
        .failed, "the window presented no frame in 2 s; is it hidden? --offscreen renders one"
    )

    /// A second render at any size. A paused offscreen frame advances no clock, so
    /// a capture does not move the simulation that a deterministic run depends on.
    private func captureOffscreen(
        _ request: AgentScreenshotRequest, gameSession: any GameSessionPort, drawableSize: CGSize
    ) throws(AgentFailure) -> AgentJSON {
        let renderer = gameSession.renderer
        let width = request.width ?? Int(drawableSize.width.rounded())
        let height = request.height ?? Int(drawableSize.height.rounded())
        guard width > 0, height > 0 else { throw hub.notReady() }
        let saved = (gameSession.worldSimPaused, renderer.uiEnabled, renderer.swfEnabled)
        gameSession.worldSimPaused = true
        if request.worldOnly {
            renderer.uiEnabled = false
            renderer.swfEnabled = false
        }
        defer {
            (gameSession.worldSimPaused, renderer.uiEnabled, renderer.swfEnabled) = saved
        }
        let texture: any MTLTexture
        do {
            texture = try renderer.renderOffscreen(width: width, height: height)
        } catch {
            throw AgentFailure(.failed, "screenshot failed: \(error.localizedDescription)")
        }
        try Self.write(texture, to: request.path)
        return Self.reply(request, texture: texture, source: "offscreen")
    }

    private static func write(_ texture: any MTLTexture, to path: String) throws(AgentFailure) {
        let url = URL(filePath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FrameScreenshot.write(texture: texture, to: url)
        } catch {
            throw AgentFailure(.failed, "screenshot failed: \(error.localizedDescription)")
        }
    }

    private static func reply(
        _ request: AgentScreenshotRequest, texture: any MTLTexture, source: String
    ) -> AgentJSON {
        [
            "path": .string(request.path), "width": .init(texture.width),
            "height": .init(texture.height), "worldOnly": .bool(request.worldOnly),
            "source": .string(source)
        ]
    }
}
