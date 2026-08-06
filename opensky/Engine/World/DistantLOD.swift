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
    /// nil means every cell in terrain block is visible. Object LOD never
    /// carries a mask: partial object-atlas blocks remain excluded.
    let clipMask: TerrainLODClipMask?

    func coversTerrain(_ cell: CellCoordinate) -> Bool {
        guard kind == .terrain else { return false }
        let inside = cell.x >= origin.x && cell.x < origin.x + level
            && cell.y >= origin.y && cell.y < origin.y + level
        guard inside else { return false }
        return clipMask?.contains(cell, blockOrigin: origin) ?? true
    }
}

nonisolated struct DistantLODBand: Equatable {
    let level: Int32
    let innerRadius: Int32
    let outerRadius: Int32
}

nonisolated enum DistantLODSelection {
    private struct Band {
        let level: Int32
        let innerRadius: Int32
        let outerRadius: Int32
    }

    private struct SelectionContext {
        let worldspace: String
        let settings: LODSettings
        let center: CellCoordinate
        let hiddenCells: Set<CellCoordinate>
        let band: Band
    }

    static func blocks(
        worldspace: String,
        settings: LODSettings,
        configuration: TerrainLODConfiguration = .fallback,
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>
    ) -> [DistantLODBlock] {
        let name = worldspace.lowercased()
        var blocks: [DistantLODBlock] = []
        for radii in bands(settings: settings, configuration: configuration) {
            let band = Band(
                level: radii.level,
                innerRadius: radii.innerRadius,
                outerRadius: radii.outerRadius
            )
            blocks.append(contentsOf: blocksForBand(
                worldspace: name,
                settings: settings,
                center: center,
                hiddenCells: hiddenCells,
                band: band
            ))
        }
        return blocks.sorted {
            ($0.level, $0.origin.x, $0.origin.y, $0.kind.rawValue)
                < ($1.level, $1.origin.x, $1.origin.y, $1.kind.rawValue)
        }
    }

    /// Maps world-unit INI thresholds onto every available LOD level. Skyrim
    /// exposes explicit L4, L8, and maximum thresholds. OpenSky splits the
    /// remaining L16/L32 interval at 2x L8 (clamped to maximum), preserving
    /// the source format's power-of-two coarsening without gaps.
    static func bands(
        settings: LODSettings,
        configuration: TerrainLODConfiguration
    ) -> [DistantLODBand] {
        guard configuration.isValid else { return [] }
        let worldDistances = [
            configuration.level0Distance,
            configuration.level1Distance,
            min(configuration.maximumDistance, configuration.level1Distance * 2),
            configuration.maximumDistance
        ]
        var inner = CellGridManager.defaultRadius
        return zip(settings.levels, worldDistances).map { level, distance in
            let requested = Int32(ceil(distance / TerrainMeshBuilder.cellSize))
            let outer = max(inner, requested)
            defer { inner = outer }
            return DistantLODBand(level: level, innerRadius: inner, outerRadius: outer)
        }
    }

    private static func blocksForBand(
        worldspace: String,
        settings: LODSettings,
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>,
        band: Band
    ) -> [DistantLODBlock] {
        let lower = settings.blockOrigin(
            containing: CellCoordinate(
                x: center.x - band.outerRadius,
                y: center.y - band.outerRadius
            ),
            level: band.level
        )
        let upper = settings.blockOrigin(
            containing: CellCoordinate(
                x: center.x + band.outerRadius,
                y: center.y + band.outerRadius
            ),
            level: band.level
        )
        var blocks: [DistantLODBlock] = []
        let context = SelectionContext(
            worldspace: worldspace,
            settings: settings,
            center: center,
            hiddenCells: hiddenCells,
            band: band
        )
        var x = lower.x
        while x <= upper.x {
            var y = lower.y
            while y <= upper.y {
                let origin = CellCoordinate(x: x, y: y)
                blocks.append(contentsOf: blocksAtOrigin(origin, context: context))
                y += band.level
            }
            x += band.level
        }
        return blocks
    }

    private static func blocksAtOrigin(
        _ origin: CellCoordinate,
        context: SelectionContext
    ) -> [DistantLODBlock] {
        let band = context.band
        guard isInsideSettings(origin, level: band.level, settings: context.settings) else {
            return []
        }
        let visible = visibleCells(
            origin: origin,
            center: context.center,
            hiddenCells: context.hiddenCells,
            band: band
        )
        guard !visible.isEmpty else { return [] }
        let mask = TerrainLODClipMask(
            level: band.level,
            blockOrigin: origin,
            visibleCells: visible
        )
        var blocks = [makeBlock(
            kind: .terrain,
            worldspace: context.worldspace,
            level: band.level,
            origin: origin,
            clipMask: mask.isComplete ? nil : mask
        )]
        // BTO atlas geometry cannot yet be clipped safely.
        if band.level <= 16, mask.isComplete {
            blocks.append(makeBlock(
                kind: .objects,
                worldspace: context.worldspace,
                level: band.level,
                origin: origin,
                clipMask: nil
            ))
        }
        return blocks
    }

    private static func makeBlock(
        kind: DistantLODBlock.Kind,
        worldspace: String,
        level: Int32,
        origin: CellCoordinate,
        clipMask: TerrainLODClipMask?
    ) -> DistantLODBlock {
        let base = "meshes\\terrain\\\(worldspace)\\"
        let folder = kind == .objects ? "objects\\" : ""
        let ext = kind == .objects ? "bto" : "btr"
        let file = "\(worldspace).\(level).\(origin.x).\(origin.y).\(ext)"
        return DistantLODBlock(
            kind: kind,
            level: level,
            origin: origin,
            path: base + folder + file,
            clipMask: clipMask
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

    private static func visibleCells(
        origin: CellCoordinate,
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>,
        band: Band
    ) -> Set<CellCoordinate> {
        var visible: Set<CellCoordinate> = []
        for x in origin.x ..< origin.x + band.level {
            for y in origin.y ..< origin.y + band.level {
                let cell = CellCoordinate(x: x, y: y)
                guard !hiddenCells.contains(cell) else { continue }
                let distance = max(
                    abs(Int64(x) - Int64(center.x)),
                    abs(Int64(y) - Int64(center.y))
                )
                let outsideInner = band.level == 4 || distance > Int64(band.innerRadius)
                if outsideInner, distance <= Int64(band.outerRadius) {
                    visible.insert(cell)
                }
            }
        }
        return visible
    }
}

nonisolated struct DistantLODScene {
    let renderScene: RenderScene
    let assets: CellAssets
    let blockCount: Int
    let missingBlockCount: Int
    let treeBlockCount: Int
    let missingTreeBlockCount: Int
    let treeInstanceCount: Int

    init(
        renderScene: RenderScene,
        assets: CellAssets,
        blockCount: Int,
        missingBlockCount: Int,
        treeBlockCount: Int = 0,
        missingTreeBlockCount: Int = 0,
        treeInstanceCount: Int = 0
    ) {
        self.renderScene = renderScene
        self.assets = assets
        self.blockCount = blockCount
        self.missingBlockCount = missingBlockCount
        self.treeBlockCount = treeBlockCount
        self.missingTreeBlockCount = missingTreeBlockCount
        self.treeInstanceCount = treeInstanceCount
    }
}

nonisolated final class DistantLODBuilder {
    let fileSystem: VirtualFileSystem
    let meshes: MeshLibrary
    private let textures: TextureLibrary
    private let configurationStore: TerrainLODConfigurationStore
    private var settingsByWorldspace: [String: LODSettings] = [:]
    var treeListByWorldspace: [String: TreeLODList] = [:]

    init(
        fileSystem: VirtualFileSystem,
        meshes: MeshLibrary,
        textures: TextureLibrary,
        configurationStore: TerrainLODConfigurationStore
    ) {
        self.fileSystem = fileSystem
        self.meshes = meshes
        self.textures = textures
        self.configurationStore = configurationStore
    }

    func build(
        worldspace: String,
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>
    ) throws -> DistantLODScene {
        _ = meshes.drainTouchedKeys()
        _ = textures.drainTouchedKeys()
        let settings = try settings(worldspace: worldspace)
        let configuration = configurationStore.snapshot().configuration
        let selected = DistantLODSelection.blocks(
            worldspace: worldspace,
            settings: settings,
            configuration: configuration,
            center: center,
            hiddenCells: hiddenCells
        )
        var placements: [RenderPlacement] = []
        var missing = 0
        for block in selected {
            do {
                try placements.append(placement(for: block))
            } catch {
                missing += 1
            }
        }
        let trees = (try? buildTrees(
            worldspace: worldspace,
            settings: settings,
            configuration: configuration,
            center: center
        )) ?? TreeBuild(placements: [], blockCount: 0, missingBlockCount: 1)
        placements.append(contentsOf: trees.placements)
        return DistantLODScene(
            renderScene: RenderScene(instances: placements),
            assets: CellAssets(
                meshKeys: meshes.drainTouchedKeys(),
                textureKeys: textures.drainTouchedKeys()
            ),
            blockCount: selected.count - missing,
            missingBlockCount: missing,
            treeBlockCount: trees.blockCount,
            missingTreeBlockCount: trees.missingBlockCount,
            treeInstanceCount: trees.placements.count
        )
    }

    private func placement(for block: DistantLODBlock) throws -> RenderPlacement {
        let model = try block.clipMask.map {
            try meshes.model(path: block.path, terrainLODClipMask: $0)
        } ?? meshes.model(path: block.path)
        // BTR vertices are block-local; BTO vertices are already world-space.
        let transform = block.kind == .terrain
            ? MatrixMath.translation(SIMD3(
                Float(block.origin.x) * TerrainMeshBuilder.cellSize,
                Float(block.origin.y) * TerrainMeshBuilder.cellSize,
                0
            ))
            : matrix_identity_float4x4
        let bounds = meshes.bounds(
            forPath: block.path,
            terrainLODClipMask: block.clipMask
        )?.transformed(by: transform)
        return RenderPlacement(
            model: model,
            transform: transform,
            bounds: bounds,
            castsShadows: false,
            receivesPointLights: false,
            receivesShadows: false
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
