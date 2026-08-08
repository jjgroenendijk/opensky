// Env-gated GRAS/LTEX + placement probe over the user's own Skyrim SE
// install (read-only external input, never committed — AGENTS.md Legal & IP).
// Skips automatically when OPENSKY_DATA_ROOT is unset/unresolvable; placement
// also requires a Metal 4 GPU. Summaries print + write to logs/.

import Foundation
import Metal
@testable import opensky
import Testing

struct GrassRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func sweepsEveryGrassAndLandTexture() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let grassRecords = records(ofType: "GRAS", in: file)
        let textureRecords = records(ofType: "LTEX", in: file)
        let grasses = try grassRecords.map(Grass.init(record:))
        let textures = try textureRecords.map(LandTexture.init(record:))
        let grassIDs = Set(grasses.map(\.formID.rawValue))

        #expect(!grasses.isEmpty, "no GRAS records in Skyrim.esm")
        #expect(!textures.isEmpty, "no LTEX records in Skyrim.esm")

        let controls = grasses.compactMap(\.placement)
        let links = textures.flatMap(\.grasses)
        let unresolved = links.count { !grassIDs.contains($0.rawValue) }
        #expect(controls.count == grasses.count, "vanilla GRAS missing DATA")
        #expect(unresolved == 0, "LTEX GNAM references missing GRAS records")

        let density = controls.map { Int($0.density) }
        let positionRange = controls.map(\.positionRange)
        let heightRange = controls.map(\.heightRange)
        let colorRange = controls.map(\.colorRange)
        let summary = """
        [INFO] Skyrim.esm grass sweep: \(grasses.count) GRAS, \(textures.count) LTEX decoded
        [INFO] LTEX GNAM links: \(links.count) (unresolved \(unresolved)); \
        LTEX with grass: \(textures.count { !$0.grasses.isEmpty })
        [INFO] density range: \(density.min() ?? 0)...\(density.max() ?? 0); \
        position range: \(minimum(positionRange))...\(maximum(positionRange))
        [INFO] height range: \(minimum(heightRange))...\(maximum(heightRange)); \
        color range: \(minimum(colorRange))...\(maximum(colorRange))
        """
        print(summary)
        try? summary.write(to: sweepLogURL, atomically: true, encoding: .utf8)
    }

    @Test(.enabled(if: Self.dataRoot != nil && Self.device != nil))
    @MainActor
    func placesFirstRenderCellDeterministically() throws {
        let root = try #require(Self.dataRoot)
        let device = try #require(Self.device)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let fileSystem = VirtualFileSystem(root: root)
        let textures = TextureLibrary(fileSystem: fileSystem, device: device)
        let meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        let builder = CellSceneBuilder(file: file, meshes: meshes, textures: textures)

        let first = try builder.buildScene(
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
            gridX: FirstRenderCell.gridX,
            gridY: FirstRenderCell.gridY
        )
        let second = try builder.buildScene(
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
            gridX: FirstRenderCell.gridX,
            gridY: FirstRenderCell.gridY
        )
        #expect(!first.grassPlacements.isEmpty, "probe cell produced no grass")
        #expect(first.grassPlacements == second.grassPlacements)
        #expect(first.summary.grassPlacementCount == first.grassPlacements.count)
        #expect(first.summary.grassTypeSkipCount == 0)

        let counts = Dictionary(grouping: first.grassPlacements, by: \.grass)
            .map { ($0.key.rawValue, $0.value.count) }
            .sorted { $0.0 < $1.0 }
            .map { String(format: "%08X:%d", $0.0, $0.1) }
            .joined(separator: " ")
        let summary = """
        [INFO] grass placement probe: \(FirstRenderCell.worldspaceEditorID) \
        (\(FirstRenderCell.gridX),\(FirstRenderCell.gridY))
        [INFO] placements: \(first.grassPlacements.count); usable types: \
        \(first.summary.grassTypeCount); skipped types: \(first.summary.grassTypeSkipCount)
        [INFO] deterministic rebuild: identical; placements by GRAS: \(counts)
        """
        print(summary)
        try? summary.write(to: placementLogURL, atomically: true, encoding: .utf8)
    }

    private func records(ofType type: FourCC, in file: ESMFile) -> [ESMRecord] {
        guard
            let top = file.topGroup(of: type),
            let children = try? top.children()
        else { return [] }
        return children.compactMap { child in
            guard case let .record(record) = child, record.type == type else { return nil }
            return record
        }
    }

    private func minimum(_ values: [Float]) -> Float {
        values.min() ?? 0
    }

    private func maximum(_ values: [Float]) -> Float {
        values.max() ?? 0
    }

    private var sweepLogURL: URL {
        logsDirectory.appending(path: "grass-sweep.log")
    }

    private var placementLogURL: URL {
        logsDirectory.appending(path: "grass-placement.log")
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
    }
}
