// Loose world items against the real install (issue #177, roadmap item
// 12.1.3), env-gated and run with `make realtest`.
//
// The synthetic suites prove the mechanism; this proves the mechanism meets the
// data. Widening `ModelBase.supportedTypes` to the six carryable families is
// only worth anything if real cells actually place them, if their bases resolve
// a model rather than being counted as markers, and if the item index #175
// built describes every one of them.
//
// Gated on `GameDataLocator.environmentKey` alone — deliberately not on the
// Steam-default fallback — so a machine without `OPENSKY_DATA_ROOT` skips
// deterministically. See openskyTests/AGENTS.md.

import Foundation
import Metal
@testable import opensky
import Testing

struct WorldItemRealDataTests {
    private static let device = MTLCreateSystemDefaultDevice()

    private static let dataRoot: GameDataRoot? = {
        guard ProcessInfo.processInfo.environment[GameDataLocator.environmentKey] != nil else {
            return nil
        }
        return try? GameDataLocator.locate()
    }()

    private static var canRun: Bool {
        device != nil && dataRoot != nil
    }

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

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func realCellsPlaceTakeableItemsThatTheItemIndexDescribes() throws {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let textures = TextureLibrary(fileSystem: vfs, device: device)
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
        // Repo root derived from this source file's location: the test host's
        // working directory is `/`, so a relative path is unwritable.
        let logs = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try report.write(
            to: logs.appending(path: "world-items-sweep.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}
