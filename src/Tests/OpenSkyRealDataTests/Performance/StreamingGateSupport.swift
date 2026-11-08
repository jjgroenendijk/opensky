// The shared setup of the streaming gates: a cold builder over the install and a
// paused offscreen session with audio and an empty Papyrus VM attached.

import CoreGraphics
import Metal
import MetalKit
import OpenSkyAudio
import OpenSkyCells
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import Testing

/// The gate budgets. The frame budget is 30 fps; the others are measured p95 plus headroom
/// (docs/tools/benchmark.md, "Real-data gates").
enum StreamingGateBudget {
    static let frameMS = 1000.0 / 30.0
    static let footprintCapMB = 2500.0
    static let collisionBuildMS = 750.0
    static let actorBuildMS = 3000.0
    static let animationUpdateMS = 4.0
    static let shadowUpdateMS = 14.0
    static let audioUpdateMS = 0.5
    static let scriptUpdateMS = 0.5
    static let size = (width: 640, height: 360)
    #if DEBUG
        static let isDebugBuild = true
    #else
        static let isDebugBuild = false
    #endif
}

@MainActor
enum StreamingGateSupport {
    static func makeBuilder() throws -> CellSceneBuilder {
        let device = try #require(RealDataEnvironment.device)
        let root = try #require(RealDataEnvironment.dataRoot)
        return try ColdCellBuilder.makeBuilder(
            root: root, loadOrder: ActiveLoadOrder.open(root: root),
            files: VirtualFileSystem(root: root), device: device, recorder: nil
        )
    }

    static func makeView() throws -> MTKView {
        let device = try #require(RealDataEnvironment.device)
        let size = StreamingGateBudget.size
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: size.width, height: size.height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return view
    }

    /// The audio engine stays disabled, so no device opens; its per-frame tick still runs.
    static func makeStreamSession() throws -> GameSession {
        let session = try GameSession(
            view: makeView(), scene: RenderScene(instances: []), movementConfiguration: .synthetic
        )
        session.worldAudio = WorldAudioEngine()
        return session
    }

    /// An empty VM, so the script budget measures the fixed engine-loop floor.
    static func attachEmptyScriptRuntime(to session: GameSession) {
        let runtime = PapyrusWorldRuntime(runtime: PapyrusRuntime(
            files: [], nativeDispatch: PapyrusNativeRegistry.standard
        ))
        session.worldTick.register(.scripts) { [runtime, weak session] delta in
            _ = runtime.advance(delta: delta, gameClock: session?.gameClock)
        }
    }
}
