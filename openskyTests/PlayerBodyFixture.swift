// Shared loading for the env-gated player-body suites (issue #189): the
// install-backed graph, the assembled body, and the bridge that binds them.
// Split out of `PlayerBodyRealDataTests` so both real-data files stay inside
// the lint size caps.
//
// Everything it reads comes from the user's own install and never enters the
// repository (AGENTS.md "Legal & IP boundary").

import Foundation
import Metal
@testable import opensky
import simd
import Testing

enum PlayerBodyFixture {
    /// The graph, the body, and the bridge feeding both, loaded from one
    /// install root.
    struct Assembled {
        let graph: PlayerBehaviorGraph
        let body: PlayerBody
        let bridge: LocomotionBridge
        let builder: CellSceneBuilder
    }

    /// How deep below the surface the injected swim plane sits. The launch cell
    /// is dry land, so the swim leg of the drive is exercised against a water
    /// height handed to the bridge rather than one read out of a WATR record.
    /// The graph, the gait resolution, and the body are the real ones; only the
    /// surface is synthetic, and it is called out here so nothing reads this as
    /// a claim about that cell's water.
    static let swimSurfaceDepth = LocomotionBridge.swimEnterDepth + 20

    @MainActor
    static func assemble(device: MTLDevice, root: GameDataRoot) throws -> Assembled {
        let vfs = VirtualFileSystem(root: root)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        let builder = CellSceneBuilder(file: file, meshes: meshes, textures: textures)
        let graph = try PlayerBehaviorGraph.load(fileSystem: vfs)
        let bridge = LocomotionBridge(
            configuration: PlayerMovementConfiguration.resolve(
                store: GameSettingLoader.load(root: root, baseFile: file),
                movementTypes: MovementTypeLoader.load(root: root, baseFile: file)
            ),
            graph: graph.instance
        )
        let result = builder.makePlayerBody(
            skeleton: graph.skeleton,
            pose: bridge.pose,
            equipped: nil
        )
        switch result {
        case let .success(body):
            return Assembled(graph: graph, body: body, bridge: bridge, builder: builder)
        case let .failure(error):
            Issue.record("player body did not assemble: \(error.localizedDescription)")
            throw error
        }
    }

    /// Every skinned mesh's current bone palette, flattened, so two poses can be
    /// compared exactly.
    static func palettes(of body: PlayerBody) -> [float4x4] {
        body.assembly.models
            .flatMap(\.asset.model.meshes)
            .filter(\.isSkinned)
            .flatMap(\.currentBoneMatrices)
    }

    /// Writes one report into gitignored `logs/`. A rendered frame or a trace of
    /// the user's own install never enters the repository.
    static func write(_ report: String, to name: String) throws {
        let directory = try logsDirectory()
        try report.write(
            to: directory.appending(path: name), atomically: true, encoding: .utf8
        )
    }

    static func logsDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        return directory
    }
}
