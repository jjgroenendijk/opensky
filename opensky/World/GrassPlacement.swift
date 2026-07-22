// Deterministic CPU grass placement for milestone 7.5.1. LAND texture
// coverage selects LTEX-linked GRAS definitions; renderer consumes these
// immutable placements through cell-owned instanced batches.
//
// Record controls: xEdit wbDefinitionsTES5.pas wbGRAS + Creation Kit Grass.
// Exact Bethesda candidate-grid/PRNG behavior is undocumented. OpenSky's
// explicit approximation + observed density evidence: docs/engine/grass.md.

import simd

/// One cell-owned grass instance before mesh loading/GPU batching.
nonisolated struct GrassPlacement: Equatable {
    let grass: FormID
    let modelPath: String
    let position: SIMD3<Float>
    let normal: SIMD3<Float>
    let yawRadians: Float
    let scale: SIMD3<Float>
    let color: SIMD3<Float>
    let wavePeriod: Float
    let flags: Grass.Flags
}

nonisolated enum GrassPlacementBuilder {
    /// Defensive floor for malformed zero/negative Position Range. This also
    /// caps one grass type at 128x128 candidates per cell before density and
    /// texture coverage reject most candidates.
    static let minimumSpacing: Float = 32
    private static let maximumAxisCandidates = 128

    private struct Source {
        let grass: Grass
        let textures: Set<FormID>
    }

    private struct Layer {
        let texture: FormID
        let opacity: [Float]
    }

    private struct Quadrant {
        var base: FormID?
        var layers: [Layer] = []
    }

    private struct GridSample {
        let first: Int
        let second: Int
        let third: Int
        let firstWeight: Float
        let secondWeight: Float
        let thirdWeight: Float
    }

    private struct PlacementContext {
        let source: Source
        let land: Land
        let heightField: TerrainHeightField
        let quadrants: [Quadrant]
        let waterHeight: Float?
        let data: Grass.PlacementData
        let modelPath: String
        let minimumSlope: Float
        let maximumSlope: Float
        let axisCount: Int
        let spacing: Float
        let jitter: Float
        let density: Float
        let origin: SIMD2<Float>
    }

    /// Pure placement pass. Dictionaries are raw-plugin indexes; generation
    /// sorts every FormID before iteration so dictionary/set order cannot
    /// perturb output.
    static func placements(
        land: Land,
        heightField: TerrainHeightField,
        landTextures: [UInt32: LandTexture],
        grasses: [UInt32: Grass],
        waterHeight: Float? = nil
    ) -> [GrassPlacement] {
        let sources = sources(
            land: land,
            landTextures: landTextures,
            grasses: grasses
        )
        guard !sources.isEmpty else { return [] }
        let quadrants = terrainQuadrants(land: land)
        var result: [GrassPlacement] = []
        for source in sources {
            result += placements(
                for: source,
                land: land,
                heightField: heightField,
                quadrants: quadrants,
                waterHeight: waterHeight
            )
        }
        return result
    }

    private static func sources(
        land: Land,
        landTextures: [UInt32: LandTexture],
        grasses: [UInt32: Grass]
    ) -> [Source] {
        let usedTextures = Set(
            land.baseTextures.map(\.texture) + land.layers.map(\.texture)
        )
        var texturesByGrass: [FormID: Set<FormID>] = [:]
        for textureID in usedTextures.sorted(by: formIDOrder) {
            guard let texture = landTextures[textureID.rawValue] else { continue }
            for grassID in texture.grasses {
                texturesByGrass[grassID, default: []].insert(textureID)
            }
        }
        return texturesByGrass.keys.sorted(by: formIDOrder).compactMap { grassID in
            guard
                let grass = grasses[grassID.rawValue],
                grass.placement != nil,
                grass.modelPath != nil,
                let textures = texturesByGrass[grassID]
            else { return nil }
            return Source(grass: grass, textures: textures)
        }
    }

    private static func placements(
        for source: Source,
        land: Land,
        heightField: TerrainHeightField,
        quadrants: [Quadrant],
        waterHeight: Float?
    ) -> [GrassPlacement] {
        guard
            let data = source.grass.placement,
            let modelPath = source.grass.modelPath,
            data.positionRange.isFinite,
            data.heightRange.isFinite,
            data.colorRange.isFinite,
            data.wavePeriod.isFinite,
            data.density > 0
        else { return [] }

        let minimumSlope = min(Float(data.minimumSlopeDegrees), 90)
        let maximumSlope = min(Float(data.maximumSlopeDegrees), 90)
        guard minimumSlope <= maximumSlope else { return [] }

        let requestedSpacing = max(data.positionRange, minimumSpacing)
        let axisCount = min(
            max(Int(ceil(TerrainMeshBuilder.cellSize / requestedSpacing)), 1),
            maximumAxisCandidates
        )
        let spacing = TerrainMeshBuilder.cellSize / Float(axisCount)
        let jitter = min(max(data.positionRange, 0), spacing) * 0.5
        let density = min(Float(data.density) / 100, 1)
        return generatePlacements(PlacementContext(
            source: source,
            land: land,
            heightField: heightField,
            quadrants: quadrants,
            waterHeight: waterHeight,
            data: data,
            modelPath: modelPath,
            minimumSlope: minimumSlope,
            maximumSlope: maximumSlope,
            axisCount: axisCount,
            spacing: spacing,
            jitter: jitter,
            density: density,
            origin: SIMD2<Float>(
                Float(heightField.coordinate.x) * TerrainMeshBuilder.cellSize,
                Float(heightField.coordinate.y) * TerrainMeshBuilder.cellSize
            )
        ))
    }

    private static func generatePlacements(_ context: PlacementContext) -> [GrassPlacement] {
        var result: [GrassPlacement] = []
        for row in 0 ..< context.axisCount {
            for column in 0 ..< context.axisCount {
                if let placement = placement(column: column, row: row, context: context) {
                    result.append(placement)
                }
            }
        }
        return result
    }

    private static func placement(
        column: Int,
        row: Int,
        context: PlacementContext
    ) -> GrassPlacement? {
        var random = StableRandom(seed: candidateSeed(
            coordinate: context.heightField.coordinate,
            land: context.land.formID,
            grass: context.source.grass.formID,
            column: column,
            row: row
        ))
        let local = candidatePosition(
            column: column,
            row: row,
            spacing: context.spacing,
            jitter: context.jitter,
            random: &random
        )
        let worldXY = context.origin + local
        guard let ground = context.heightField.sample(at: worldXY) else { return nil }
        let coverage = textureCoverage(
            at: local,
            matching: context.source.textures,
            quadrants: context.quadrants
        )
        guard coverage > 0, random.unitFloat() < context.density * coverage else {
            return nil
        }
        let slope = slopeDegrees(normal: ground.normal)
        guard slope >= context.minimumSlope, slope <= context.maximumSlope else {
            return nil
        }
        guard
            passesWaterRule(
                height: ground.height,
                waterHeight: context.waterHeight,
                data: context.data
            ) else { return nil }

        let scale = instanceScale(data: context.data, random: &random)
        let color = vertexColor(land: context.land, at: local)
            * colorMultiplier(range: context.data.colorRange, random: &random)
        return GrassPlacement(
            grass: context.source.grass.formID,
            modelPath: context.modelPath,
            position: SIMD3(worldXY.x, worldXY.y, ground.height),
            normal: ground.normal,
            yawRadians: random.unitFloat() * 2 * .pi,
            scale: scale,
            color: color,
            wavePeriod: context.data.wavePeriod,
            flags: context.data.flags
        )
    }

    private static func candidatePosition(
        column: Int,
        row: Int,
        spacing: Float,
        jitter: Float,
        random: inout StableRandom
    ) -> SIMD2<Float> {
        let center = SIMD2<Float>(
            (Float(column) + 0.5) * spacing,
            (Float(row) + 0.5) * spacing
        )
        let offset = SIMD2<Float>(
            (random.unitFloat() * 2 - 1) * jitter,
            (random.unitFloat() * 2 - 1) * jitter
        )
        let edge = TerrainMeshBuilder.cellSize.nextDown
        return simd_clamp(center + offset, .zero, SIMD2(repeating: edge))
    }
}

// MARK: - LAND texture coverage

nonisolated extension GrassPlacementBuilder {
    private static func terrainQuadrants(land: Land) -> [Quadrant] {
        var result = [Quadrant](repeating: Quadrant(), count: 4)
        for base in land.baseTextures where base.quadrant < 4 {
            if result[Int(base.quadrant)].base == nil {
                result[Int(base.quadrant)].base = base.texture
            }
        }
        for layer in land.layers.sorted(by: layerOrder) where layer.quadrant < 4 {
            result[Int(layer.quadrant)].layers.append(Layer(
                texture: layer.texture,
                opacity: TerrainMeshBuilder.denseOpacities(layer.alphas)
            ))
        }
        return result
    }

    /// Mirrors terrainFragment's ordered lerps, retaining each LTEX's final
    /// contribution rather than only the resulting RGB.
    private static func textureCoverage(
        at local: SIMD2<Float>,
        matching textures: Set<FormID>,
        quadrants: [Quadrant]
    ) -> Float {
        let east = local.x >= TerrainMeshBuilder.cellSize * 0.5
        let north = local.y >= TerrainMeshBuilder.cellSize * 0.5
        let quadrantIndex = (north ? 2 : 0) + (east ? 1 : 0)
        let quadrant = quadrants[quadrantIndex]
        var weights: [FormID: Float] = [:]
        if let base = quadrant.base {
            weights[base] = 1
        }
        let quadrantOrigin = SIMD2<Float>(
            east ? TerrainMeshBuilder.cellSize * 0.5 : 0,
            north ? TerrainMeshBuilder.cellSize * 0.5 : 0
        )
        let sample = gridSample(
            at: local - quadrantOrigin,
            dimension: TerrainMeshBuilder.quadrantDimension
        )
        for layer in quadrant.layers {
            let opacity = scalarSample(layer.opacity, at: sample)
            for texture in weights.keys {
                weights[texture, default: 0] *= 1 - opacity
            }
            weights[layer.texture, default: 0] += opacity
        }
        return min(weights.reduce(0) { partial, entry in
            textures.contains(entry.key) ? partial + entry.value : partial
        }, 1)
    }
}

// MARK: - Terrain attributes + GRAS controls

nonisolated extension GrassPlacementBuilder {
    private static func vertexColor(land: Land, at local: SIMD2<Float>) -> SIMD3<Float> {
        guard let colors = land.colors, colors.count == Land.vertexCount else {
            return SIMD3(repeating: 1)
        }
        let sample = gridSample(at: local, dimension: Land.dimension)
        func color(_ index: Int) -> SIMD3<Float> {
            let value = colors[index]
            return SIMD3(Float(value.x), Float(value.y), Float(value.z)) / 255
        }
        return color(sample.first) * sample.firstWeight
            + color(sample.second) * sample.secondWeight
            + color(sample.third) * sample.thirdWeight
    }

    private static func instanceScale(
        data: Grass.PlacementData,
        random: inout StableRandom
    ) -> SIMD3<Float> {
        let variation = abs(data.heightRange)
        let heightScale = max(0.05, 1 + (random.unitFloat() * 2 - 1) * variation)
        if data.flags.contains(.uniformScaling) {
            return SIMD3(repeating: heightScale)
        }
        return SIMD3(1, 1, heightScale)
    }

    private static func colorMultiplier(
        range: Float,
        random: inout StableRandom
    ) -> Float {
        1 - random.unitFloat() * min(max(range, 0), 1)
    }

    private static func slopeDegrees(normal: SIMD3<Float>) -> Float {
        acos(min(max(normal.z, -1), 1)) * 180 / .pi
    }

    private static func passesWaterRule(
        height: Float,
        waterHeight: Float?,
        data: Grass.PlacementData
    ) -> Bool {
        guard let waterHeight, waterHeight.isFinite else { return true }
        let delta = height - waterHeight
        let distance = Float(data.unitsFromWater)
        return switch data.waterRule {
        case .aboveAtLeast: delta >= distance
        case .aboveAtMost: delta >= 0 && delta <= distance
        case .belowAtLeast: delta <= -distance
        case .belowAtMost: delta <= 0 && delta >= -distance
        case .eitherAtLeast: abs(delta) >= distance
        case .eitherAtMost: abs(delta) <= distance
        case .eitherAtMostAbove: delta <= 0 || delta <= distance
        case .eitherAtMostBelow: delta >= 0 || delta >= -distance
        case .unknown: true
        }
    }
}

// MARK: - Grid interpolation + deterministic random

nonisolated extension GrassPlacementBuilder {
    /// Triangle interpolation matches TerrainMeshBuilder and
    /// TerrainHeightField's SW-NE diagonal, not bilinear sampling.
    private static func gridSample(at local: SIMD2<Float>, dimension: Int) -> GridSample {
        let maximumCell = dimension - 2
        let x = min(max(local.x / TerrainMeshBuilder.quadSize, 0), Float(dimension - 1))
        let y = min(max(local.y / TerrainMeshBuilder.quadSize, 0), Float(dimension - 1))
        let column = min(Int(x.rounded(.down)), maximumCell)
        let row = min(Int(y.rounded(.down)), maximumCell)
        let fractionX = min(max(x - Float(column), 0), 1)
        let fractionY = min(max(y - Float(row), 0), 1)
        let southWest = row * dimension + column
        let southEast = southWest + 1
        let northWest = southWest + dimension
        let northEast = northWest + 1
        if fractionY <= fractionX {
            return GridSample(
                first: southWest,
                second: southEast,
                third: northEast,
                firstWeight: 1 - fractionX,
                secondWeight: fractionX - fractionY,
                thirdWeight: fractionY
            )
        }
        return GridSample(
            first: southWest,
            second: northEast,
            third: northWest,
            firstWeight: 1 - fractionY,
            secondWeight: fractionX,
            thirdWeight: fractionY - fractionX
        )
    }

    private static func scalarSample(_ values: [Float], at sample: GridSample) -> Float {
        guard
            sample.first < values.count,
            sample.second < values.count,
            sample.third < values.count
        else { return 0 }
        let value = values[sample.first] * sample.firstWeight
            + values[sample.second] * sample.secondWeight
            + values[sample.third] * sample.thirdWeight
        return min(max(value, 0), 1)
    }

    private static func candidateSeed(
        coordinate: CellCoordinate,
        land: FormID,
        grass: FormID,
        column: Int,
        row: Int
    ) -> UInt64 {
        let cell = UInt64(UInt32(bitPattern: coordinate.x)) << 32
            | UInt64(UInt32(bitPattern: coordinate.y))
        let candidate = UInt64(row) << 32 | UInt64(column)
        return cell
            ^ UInt64(land.rawValue) &* 0x9E37_79B9_7F4A_7C15
            ^ UInt64(grass.rawValue) &* 0xD1B5_4A32_D192_ED03
            ^ candidate &* 0x94D0_49BB_1331_11EB
    }

    private static func formIDOrder(_ lhs: FormID, _ rhs: FormID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    private static func layerOrder(_ lhs: Land.TextureLayer, _ rhs: Land.TextureLayer) -> Bool {
        if lhs.quadrant != rhs.quadrant {
            return lhs.quadrant < rhs.quadrant
        }
        return lhs.layer < rhs.layer
    }
}

/// SplitMix64: compact, platform-stable stream. Swift's Hasher is deliberately
/// randomized per process and cannot seed persistent cell placement.
nonisolated private struct StableRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func unitFloat() -> Float {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Float(value >> 40) / Float(1 << 24)
    }
}
