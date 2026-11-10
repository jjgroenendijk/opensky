// Distant terrain/object LOD selection + scene build. Block grids are
// anchored at lodsettings origin; each level-N asset spans N x N exterior
// cells. Ring bands begin outside loaded 5x5 and get coarser with distance.

import Foundation
public import OpenSkyFormatsCore
public import OpenSkyFormatsMesh
public import OpenSkyGameData
public import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkyRenderResources
import simd

nonisolated public struct DistantLODBlock: Equatable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case terrain
        case objects
    }

    public let kind: Kind
    public let level: Int32
    public let origin: CellCoordinate
    public let path: String
    /// nil means every cell in terrain block is visible. Object LOD never
    /// carries a mask: partial object-atlas blocks remain excluded.
    public let clipMask: TerrainLODClipMask?

    func coversTerrain(_ cell: CellCoordinate) -> Bool {
        guard kind == .terrain else { return false }
        let inside = cell.x >= origin.x && cell.x < origin.x + level
            && cell.y >= origin.y && cell.y < origin.y + level
        guard inside else { return false }
        return clipMask?.contains(cell, blockOrigin: origin) ?? true
    }
}

nonisolated public struct DistantLODBand: Equatable, Sendable {
    public let level: Int32
    public let innerRadius: Int32
    public let outerRadius: Int32
}

nonisolated public enum DistantLODSelection: Sendable {
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

    public static func blocks(
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
                around: (center, hiddenCells),
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
    /// remaining L16/L32 interval at 2x L8; `fSplitDistanceMult` scales each split.
    public static func bands(
        settings: LODSettings,
        configuration: TerrainLODConfiguration
    ) -> [DistantLODBand] {
        guard configuration.isValid else { return [] }
        let split = configuration.splitDistanceMultiplier
        let worldDistances = [
            configuration.level0Distance * split,
            configuration.level1Distance * split,
            configuration.level1Distance * 2 * split,
            configuration.maximumDistance
        ].map { min($0, configuration.maximumDistance) }
        var inner = configuration.loadedGridRadius
        // The finest band keeps at least one ring, so a small split never puts a coarse
        // block, with its cracks, against the full-detail cells.
        var least = inner + 1
        return zip(settings.levels, worldDistances).map { level, distance in
            let requested = Int32(ceil(distance / TerrainMeshBuilder.cellSize))
            let outer = max(inner, requested, least)
            least = 0
            defer { inner = outer }
            return DistantLODBand(level: level, innerRadius: inner, outerRadius: outer)
        }
    }

    private static func blocksForBand(
        worldspace: String,
        settings: LODSettings,
        around view: (center: CellCoordinate, hiddenCells: Set<CellCoordinate>),
        band: Band
    ) -> [DistantLODBlock] {
        let (center, hiddenCells) = view
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
            at: (band.level, origin),
            clipMask: mask.isComplete ? nil : mask
        )]
        // BTO atlas geometry cannot yet be clipped safely.
        if band.level <= 16, mask.isComplete {
            blocks.append(makeBlock(
                kind: .objects,
                worldspace: context.worldspace,
                at: (band.level, origin),
                clipMask: nil
            ))
        }
        return blocks
    }

    private static func makeBlock(
        kind: DistantLODBlock.Kind,
        worldspace: String,
        at place: (level: Int32, origin: CellCoordinate),
        clipMask: TerrainLODClipMask?
    ) -> DistantLODBlock {
        let (level, origin) = place
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

nonisolated public struct DistantLODScene: Sendable {
    public let renderScene: RenderScene
    public let assets: CellAssets
    public let blockCount: Int
    public let missingBlockCount: Int
    public let treeBlockCount: Int
    public let missingTreeBlockCount: Int
    public let treeInstanceCount: Int
    /// Cells past the loaded grid whose large references draw their full model.
    public let largeReferenceCells: Set<CellCoordinate>
    /// Built without the large-reference ring, which a later build adds.
    public let largeReferencesPending: Bool
    /// Large references drawn with their full model.
    public let largeReferenceCount: Int
    /// Cell segments of object LOD large-reference shapes the ring hid.
    public let hiddenLargeReferenceSegments: Int
    /// Is Full LOD references drawn past the loaded grid.
    public private(set) var fullLODReferenceCount = 0
    /// Terrain blocks drawn from the generated LOD instead of the vanilla files.
    public internal(set) var generatedTerrainBlockCount = 0
    /// Object IDs whose enable change must rebuild the ring.
    public private(set) var watchedObjectIDs: Set<UInt32> = []

    public init(
        renderScene: RenderScene,
        assets: CellAssets,
        blockCount: Int,
        missingBlockCount: Int,
        treeBlockCount: Int = 0,
        missingTreeBlockCount: Int = 0,
        treeInstanceCount: Int = 0,
        largeReferenceCells: Set<CellCoordinate> = [],
        largeReferencesPending: Bool = false,
        largeReferenceCount: Int = 0,
        hiddenLargeReferenceSegments: Int = 0
    ) {
        self.renderScene = renderScene
        self.assets = assets
        self.blockCount = blockCount
        self.missingBlockCount = missingBlockCount
        self.treeBlockCount = treeBlockCount
        self.missingTreeBlockCount = missingTreeBlockCount
        self.treeInstanceCount = treeInstanceCount
        self.largeReferenceCells = largeReferenceCells
        self.largeReferencesPending = largeReferencesPending
        self.largeReferenceCount = largeReferenceCount
        self.hiddenLargeReferenceSegments = hiddenLargeReferenceSegments
    }

    /// The same ring, drawn with the worldspace's fitted terrain LOD curve.
    public func with(terrainLODBrightness: TerrainLODBrightness) -> DistantLODScene {
        var scene = renderScene
        scene.terrainLODBrightness = terrainLODBrightness
        return replacing(renderScene: scene)
    }

    /// The same ring with distant water planes added.
    public func adding(water: [WaterDrawItem]) -> DistantLODScene {
        replacing(renderScene: RenderScene(merging: [
            renderScene, RenderScene(instances: [], water: water)
        ]))
    }

    /// The same ring with the full models of its large references, and their assets.
    public func adding(largeReferences: [RenderPlacement], assets added: CellAssets)
        -> DistantLODScene
    {
        guard !largeReferences.isEmpty else { return self }
        return replacing(
            renderScene: RenderScene(merging: [
                renderScene, RenderScene(instances: largeReferences)
            ]),
            assets: CellAssets(
                meshKeys: assets.meshKeys.union(added.meshKeys),
                textureKeys: assets.textureKeys.union(added.textureKeys)
            ),
            largeReferenceCount: largeReferenceCount + largeReferences.count
        )
    }

    /// The same ring with the Is Full LOD references past the loaded grid, and their assets.
    public func adding(fullLODReferences: [RenderPlacement], assets added: CellAssets)
        -> DistantLODScene
    {
        guard !fullLODReferences.isEmpty else { return self }
        var scene = replacing(
            renderScene: RenderScene(merging: [
                renderScene, RenderScene(instances: fullLODReferences)
            ]),
            assets: CellAssets(
                meshKeys: assets.meshKeys.union(added.meshKeys),
                textureKeys: assets.textureKeys.union(added.textureKeys)
            )
        )
        scene.fullLODReferenceCount = fullLODReferenceCount + fullLODReferences.count
        return scene
    }

    private func replacing(
        renderScene: RenderScene,
        assets: CellAssets? = nil,
        largeReferenceCount: Int? = nil
    ) -> DistantLODScene {
        var scene = DistantLODScene(
            renderScene: renderScene,
            assets: assets ?? self.assets,
            blockCount: blockCount,
            missingBlockCount: missingBlockCount,
            treeBlockCount: treeBlockCount,
            missingTreeBlockCount: missingTreeBlockCount,
            treeInstanceCount: treeInstanceCount,
            largeReferenceCells: largeReferenceCells,
            largeReferencesPending: largeReferencesPending,
            largeReferenceCount: largeReferenceCount ?? self.largeReferenceCount,
            hiddenLargeReferenceSegments: hiddenLargeReferenceSegments
        )
        scene.fullLODReferenceCount = fullLODReferenceCount
        scene.generatedTerrainBlockCount = generatedTerrainBlockCount
        scene.watchedObjectIDs = watchedObjectIDs
        return scene
    }

    /// The same ring, rebuilt when one of `objectIDs` is enabled or disabled.
    public func watching(_ objectIDs: Set<UInt32>) -> DistantLODScene {
        var scene = self
        scene.watchedObjectIDs.formUnion(objectIDs)
        return scene
    }
}

nonisolated public final class DistantLODBuilder {
    public let fileSystem: any GameFileSource
    public let meshes: MeshLibrary
    let textures: TextureLibrary
    public let configurationStore: TerrainLODConfigurationStore
    private var settingsByWorldspace: [String: LODSettings] = [:]
    var treeListByWorldspace: [String: TreeLODList] = [:]

    public init(
        fileSystem: any GameFileSource,
        meshes: MeshLibrary,
        textures: TextureLibrary,
        configurationStore: TerrainLODConfigurationStore
    ) {
        self.fileSystem = fileSystem
        self.meshes = meshes
        self.textures = textures
        self.configurationStore = configurationStore
    }

    /// What a second builder needs to build the first ring off the build queue.
    public func prebuild(worldspace: String) -> DistantLODPrebuild {
        DistantLODPrebuild(
            fileSystem: fileSystem,
            device: meshes.device,
            cache: textures.assetCache,
            configurationStore: configurationStore,
            worldspace: worldspace
        )
    }

    /// Without `largeReferences`, the object LOD keeps its large-reference shapes.
    /// `terrain` generates a terrain block from the load order; nil, or a block it cannot
    /// make, draws the vanilla file.
    public func build(
        worldspace: String,
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>,
        largeReferences: Bool = true,
        terrain: any TerrainLODGenerating? = nil
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
        // The NIF decode fans out; the clip to the visible cells stays in the serial load.
        meshes.predecode(paths: selected.lazy.filter {
            (terrain == nil || $0.kind != .terrain)
                && self.meshes.bounds(forPath: $0.path, terrainLODClipMask: $0.clipMask) == nil
        }.map(\.path))
        defer { meshes.dropPredecoded() }
        let largeRadius = configuration.largeReferenceRadius
        let ringWanted = largeRadius > configuration.loadedGridRadius
        let ringActive = ringWanted && largeReferences
        let unhidden = LargeReferenceHiding(center: center, radius: largeRadius)
        let blocks = blockPlacements(selected, terrain: terrain, ring: ringActive ? unhidden : nil)
        let ring = blocks.ring ?? unhidden
        var placements = blocks.placements
        let missing = blocks.missing
        let trees = attempt {
            try buildTrees(
                worldspace: worldspace,
                settings: settings,
                configuration: configuration,
                around: (center, hiddenCells)
            )
        } ?? TreeBuild(placements: [], blockCount: 0, missingBlockCount: 1)
        placements.append(contentsOf: trees.placements)
        var scene = DistantLODScene(
            renderScene: RenderScene(instances: placements),
            assets: CellAssets(
                meshKeys: meshes.drainTouchedKeys(),
                textureKeys: textures.drainTouchedKeys()
            ),
            blockCount: selected.count - missing,
            missingBlockCount: missing,
            treeBlockCount: trees.blockCount,
            missingTreeBlockCount: trees.missingBlockCount,
            treeInstanceCount: trees.placements.count,
            largeReferenceCells: ringActive ? LargeReferenceRing.cells(
                center: center, radii: (largeRadius, configuration.loadedGridRadius),
                hiddenCells: hiddenCells, blocks: ring.wholeBlocks
            ) : [],
            largeReferencesPending: ringWanted && !largeReferences,
            hiddenLargeReferenceSegments: ring.hiddenSegments
        )
        scene.generatedTerrainBlockCount = blocks.generated
        return scene
    }

    /// One placement per block: a generated terrain block where `terrain` makes one, else
    /// the block's file. `ring` hides the large references the block's cells hold.
    private func blockPlacements(
        _ selected: [DistantLODBlock],
        terrain: any TerrainLODGenerating?,
        ring start: LargeReferenceHiding?
    ) -> BlockPlacements {
        var placements: [RenderPlacement] = []
        var missing = 0
        var generated = 0
        var ring = start
        for block in selected {
            let hides = ring.map {
                LargeReferenceRing.hidesLargeReferences(
                    of: block, center: $0.center, radius: $0.radius
                )
            } ?? false
            do {
                if
                    block.kind == .terrain, let terrain,
                    let made = try generatedPlacement(for: block, terrain: terrain)
                {
                    placements.append(made)
                    generated += 1
                    continue
                }
                try placements.append(placement(
                    for: block, hiding: hides ? { ring?.hiding($0, of: block) ?? $0 } : nil
                ))
            } catch {
                missing += 1
            }
        }
        return BlockPlacements(
            placements: placements, missing: missing, generated: generated, ring: ring
        )
    }

    /// `hiding` takes the full model and returns the one to draw.
    func placement(
        for block: DistantLODBlock,
        hiding: ((RenderModel) -> RenderModel)?
    ) throws -> RenderPlacement {
        let full = try block.clipMask.map {
            try meshes.model(path: block.path, terrainLODClipMask: $0)
        } ?? meshes.model(path: block.path)
        let model = hiding?(full) ?? full
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
            receivesShadows: false,
            layer: .distantLOD
        )
    }

    /// The cells the worldspace's LOD covers, from its `lodsettings` file.
    public func area(worldspace: String) -> LODWaterLayout.Rectangle? {
        guard let settings = attempt({ try settings(worldspace: worldspace) }) else { return nil }
        return LODWaterLayout.Rectangle(
            origin: settings.origin, width: settings.stride, height: settings.stride
        )
    }

    func settings(worldspace: String) throws -> LODSettings {
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

nonisolated private struct BlockPlacements {
    let placements: [RenderPlacement]
    let missing: Int
    let generated: Int
    let ring: LargeReferenceHiding?
}
