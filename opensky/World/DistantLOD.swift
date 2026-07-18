// Distant terrain/object LOD selection + scene build. Block grids are
// anchored at lodsettings origin; each level-N asset spans N x N exterior
// cells. Ring bands begin outside loaded 5x5 and get coarser with distance.

import Foundation
import simd

nonisolated struct DistantLODBlock: Equatable, Hashable {
    enum Kind: String {
        case terrain
        case objects
    }

    let kind: Kind
    let level: Int32
    let origin: CellCoordinate
    let path: String
}

nonisolated enum DistantLODSelection {
    /// Plain initial distance constants in cells. INI fidelity arrives later.
    private static let outerRadius: [Int32: Int32] = [4: 8, 8: 16, 16: 32, 32: 64]
    private static let innerRadius: [Int32: Int32] = [4: 2, 8: 8, 16: 16, 32: 32]

    static func blocks(
        worldspace: String,
        settings: LODSettings,
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>
    ) -> [DistantLODBlock] {
        let name = worldspace.lowercased()
        var blocks: [DistantLODBlock] = []
        for level in settings.levels {
            guard
                let inner = innerRadius[level],
                let outer = outerRadius[level]
            else { continue }
            let lower = settings.blockOrigin(
                containing: CellCoordinate(x: center.x - outer, y: center.y - outer),
                level: level
            )
            let upper = settings.blockOrigin(
                containing: CellCoordinate(x: center.x + outer, y: center.y + outer),
                level: level
            )
            var x = lower.x
            while x <= upper.x {
                var y = lower.y
                while y <= upper.y {
                    let origin = CellCoordinate(x: x, y: y)
                    let inside = isInsideSettings(origin, level: level, settings: settings)
                    let distance = minimumDistance(from: center, to: origin, level: level)
                    let hidden = intersects(origin: origin, level: level, cells: hiddenCells)
                    if inside, distance > inner, !hidden {
                        blocks.append(makeBlock(
                            kind: .terrain,
                            worldspace: name,
                            level: level,
                            origin: origin
                        ))
                        if level <= 16 {
                            blocks.append(makeBlock(
                                kind: .objects,
                                worldspace: name,
                                level: level,
                                origin: origin
                            ))
                        }
                    }
                    y += level
                }
                x += level
            }
        }
        return blocks.sorted {
            ($0.level, $0.origin.x, $0.origin.y, $0.kind.rawValue)
                < ($1.level, $1.origin.x, $1.origin.y, $1.kind.rawValue)
        }
    }

    private static func makeBlock(
        kind: DistantLODBlock.Kind,
        worldspace: String,
        level: Int32,
        origin: CellCoordinate
    ) -> DistantLODBlock {
        let base = "meshes\\terrain\\\(worldspace)\\"
        let folder = kind == .objects ? "objects\\" : ""
        let ext = kind == .objects ? "bto" : "btr"
        let file = "\(worldspace).\(level).\(origin.x).\(origin.y).\(ext)"
        return DistantLODBlock(
            kind: kind,
            level: level,
            origin: origin,
            path: base + folder + file
        )
    }

    private static func isInsideSettings(
        _ origin: CellCoordinate,
        level: Int32,
        settings: LODSettings
    ) -> Bool {
        let limitX = Int64(settings.origin.x) + Int64(settings.stride)
        let limitY = Int64(settings.origin.y) + Int64(settings.stride)
        return origin.x >= settings.origin.x && origin.y >= settings.origin.y
            && Int64(origin.x) + Int64(level) <= limitX
            && Int64(origin.y) + Int64(level) <= limitY
    }

    private static func minimumDistance(
        from cell: CellCoordinate,
        to origin: CellCoordinate,
        level: Int32
    ) -> Int32 {
        let maxX = origin.x + level - 1
        let maxY = origin.y + level - 1
        let dx = cell.x < origin.x ? origin.x - cell.x : max(0, cell.x - maxX)
        let dy = cell.y < origin.y ? origin.y - cell.y : max(0, cell.y - maxY)
        return max(dx, dy)
    }

    private static func intersects(
        origin: CellCoordinate,
        level: Int32,
        cells: Set<CellCoordinate>
    ) -> Bool {
        let maxX = origin.x + level
        let maxY = origin.y + level
        return cells.contains {
            $0.x >= origin.x && $0.x < maxX && $0.y >= origin.y && $0.y < maxY
        }
    }
}

nonisolated struct DistantLODScene {
    let renderScene: RenderScene
    let assets: CellAssets
    let blockCount: Int
    let missingBlockCount: Int
}

nonisolated final class DistantLODBuilder {
    private let fileSystem: VirtualFileSystem
    private let meshes: MeshLibrary
    private let textures: TextureLibrary
    private var settingsByWorldspace: [String: LODSettings] = [:]

    init(fileSystem: VirtualFileSystem, meshes: MeshLibrary, textures: TextureLibrary) {
        self.fileSystem = fileSystem
        self.meshes = meshes
        self.textures = textures
    }

    func build(
        worldspace: String,
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>
    ) throws -> DistantLODScene {
        _ = meshes.drainTouchedKeys()
        _ = textures.drainTouchedKeys()
        let settings = try settings(worldspace: worldspace)
        let selected = DistantLODSelection.blocks(
            worldspace: worldspace,
            settings: settings,
            center: center,
            hiddenCells: hiddenCells
        )
        var placements: [RenderPlacement] = []
        var missing = 0
        for block in selected {
            do {
                let model = try meshes.model(path: block.path)
                // .btr terrain vertices are block-local; .bto object vertices
                // are already world-space (xLODGen generator + vanilla probe).
                let transform = block.kind == .terrain
                    ? MatrixMath.translation(SIMD3(
                        Float(block.origin.x) * TerrainMeshBuilder.cellSize,
                        Float(block.origin.y) * TerrainMeshBuilder.cellSize,
                        0
                    ))
                    : matrix_identity_float4x4
                let bounds = meshes.bounds(forPath: block.path)?.transformed(by: transform)
                placements.append(RenderPlacement(
                    model: model,
                    transform: transform,
                    bounds: bounds
                ))
            } catch {
                missing += 1
            }
        }
        return DistantLODScene(
            renderScene: RenderScene(instances: placements),
            assets: CellAssets(
                meshKeys: meshes.drainTouchedKeys(),
                textureKeys: textures.drainTouchedKeys()
            ),
            blockCount: placements.count,
            missingBlockCount: missing
        )
    }

    private func settings(worldspace: String) throws -> LODSettings {
        let key = worldspace.lowercased()
        if let cached = settingsByWorldspace[key] {
            return cached
        }
        let data = try fileSystem.contents(forPath: "lodsettings\\\(key).lod")
        let parsed = try LODSettings(data: data)
        settingsByWorldspace[key] = parsed
        return parsed
    }
}
