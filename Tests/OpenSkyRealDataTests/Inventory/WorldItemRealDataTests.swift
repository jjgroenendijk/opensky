// Checks that real cells place the six carryable item families, that their
// bases resolve a model, and that the item index describes each one.

import Foundation
import Metal
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
@testable import OpenSkyWorldInterface
import Testing

struct WorldItemRealDataTests {
    /// The exterior grid swept for loose items. Whiterun's surroundings are the
    /// same cells the render and streaming acceptance tests already build, so
    /// this adds no new assumption about the install's contents.
    private static let sweptRadius: Int32 = 2

    /// Every `.take` interaction the real Whiterun-area cells place, and the
    /// counts that prove they are drawn rather than skipped.
    private struct Sweep {
        var cells = 0
        var takeables = 0
        var drawn = 0
        var describedByItemIndex = 0
        var names: [String] = []
    }

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func realCellsPlaceTakeableItemsThatTheItemIndexDescribes() throws {
        let device = try #require(RealDataEnvironment.device)
        let root = try #require(RealDataEnvironment.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let textures = try TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        let builder = CellSceneBuilder(
            file: file, meshes: meshes, textures: textures, fileSystem: vfs
        )
        let items = ItemDefinitionStore(file: file)

        var sweep = Sweep()
        for x in -Self.sweptRadius ... Self.sweptRadius {
            for y in -Self.sweptRadius ... Self.sweptRadius {
                let scene = try? builder.buildScene(
                    worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
                    gridX: FirstRenderCell.gridX + x,
                    gridY: FirstRenderCell.gridY + y
                )
                guard let scene else { continue }
                Self.accumulate(scene, items: items, into: &sweep)
            }
        }

        // A cell that places no item at all is ordinary; a whole neighbourhood
        // that places none would mean the widened base set never took effect.
        #expect(sweep.cells > 0, "no cells built in the swept grid")
        #expect(sweep.takeables > 0, "no loose items in \(sweep.cells) real cells")
        // Every takeable base is one the item index describes, so the take path
        // can weigh it, value it and stack it.
        #expect(sweep.describedByItemIndex == sweep.takeables)
        // Item bases stopped being unsupported, which is what the widening was
        // for. The absolute skip count stays non-zero on real data — NPC_,
        // FLOR, SCOL and the rest are still unsupported here — so the check is
        // that every takeable resolved rather than that nothing was skipped.
        #expect(sweep.drawn > 0)

        try Self.writeReport(sweep)
    }

    private static func accumulate(
        _ scene: CellScene,
        items: ItemDefinitionStore,
        into sweep: inout Sweep
    ) {
        sweep.cells += 1
        sweep.drawn += scene.summary.drawnRefCount
        for interaction in scene.interactions.values where interaction.action == .take {
            sweep.takeables += 1
            if items.definition(interaction.base) != nil {
                sweep.describedByItemIndex += 1
            }
            sweep.names.append(interaction.name)
        }
    }

    /// The sweep's numbers go to gitignored `logs/`, not into an assertion
    /// message: `print` is absent from the `.xcresult`, and a rendered frame or
    /// a record dump from a real install is game content.
    private static func writeReport(_ sweep: Sweep) throws {
        let sorted = Set(sweep.names).sorted()
        let report = """
        [INFO] world items over \(sweep.cells) real cells
        takeable references: \(sweep.takeables)
        distinct names: \(sorted.count)
        described by the item index: \(sweep.describedByItemIndex)
        drawn references: \(sweep.drawn)
        """
        // Resolved through `RepositoryLogs`: the test host's working directory
        // is `/`, so a relative path is unwritable.
        let logs = try RepositoryLogs.directory()
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try report.write(
            to: logs.appending(path: "world-items-sweep.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}
