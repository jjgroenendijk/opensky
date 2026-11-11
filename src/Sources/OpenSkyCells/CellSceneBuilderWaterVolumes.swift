// The water boxes of one cell: its own water, placed water activators, and the
// boxes of current planes. See docs/engine/water-physics.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyPhysics
import OpenSkyRenderCore
import simd

nonisolated extension CellWaterBuilder {
    /// How deep a cell's water box reaches when the cell has no land to measure.
    static let cellWaterFallbackDepth: Float = 4096

    /// An exterior cell's boxes, from its water and land.
    nonisolated func waterVolumes(
        _ refs: [PlacedReference], found: FoundCell, in environment: EnvironmentBuild
    ) -> WaterVolumeSet {
        buildWaterVolumes(
            refs: refs, cellWater: environment.water, grid: found.cell.grid,
            terrain: environment.terrain?.heightField
        )
    }

    nonisolated func buildWaterVolumes(
        refs: [PlacedReference], cellWater: WaterBuild?, grid: Cell.Grid?,
        terrain: TerrainHeightField?
    ) -> WaterVolumeSet {
        var volumes: [WaterVolume] = []
        if let cellWater, let grid, let box = cellWaterVolume(
            cellWater,
            grid: grid,
            terrain: terrain
        ) {
            volumes.append(box)
        }
        volumes += placedWaterVolumes(refs: refs)
        return WaterVolumeSet(volumes: volumes)
    }

    /// The cell's square from its lowest land up to its water height, with the
    /// water type's `NAM0` and `NAM1` as one current over all of it.
    private func cellWaterVolume(
        _ water: WaterBuild, grid: Cell.Grid, terrain: TerrainHeightField?
    ) -> WaterVolume? {
        let size = TerrainMeshBuilder.cellSize
        let floor = min(
            terrain?.heights.min() ?? water.height - Self.cellWaterFallbackDepth, water.height - 1
        )
        let half = SIMD3(size / 2, size / 2, (water.height - floor) / 2)
        let centre = SIMD3(
            Float(grid.x) * size + half.x, Float(grid.y) * size + half.y, floor + half.z
        )
        let type = water.waterType.flatMap { waterTypeIndexBuildingIfNeeded()[$0.rawValue] }
        let currents = type.map { [Self.cellCurrent($0.details)] } ?? []
        return WaterVolume(
            transform: MatrixMath.translation(centre), halfExtents: half, surface: water.height,
            currents: currents, waterType: water.waterType,
            isDangerous: type.map { $0.details.flags & 0x1 != 0 } ?? false
        )
    }

    private static func cellCurrent(_ details: WaterDetails) -> WaterCurrent {
        WaterCurrent(
            shape: .everywhere,
            linear: (details.linearVelocity ?? .zero) * NIFCollisionModel.havokToEngineScale,
            angular: details.angularVelocity ?? .zero
        )
    }

    /// Placed water and current planes, from each reference's root collision.
    private func placedWaterVolumes(refs: [PlacedReference]) -> [WaterVolume] {
        guard let collisionModels = owner.collisionModels else { return [] }
        let bases = owner.recordIndex.modelBaseIndexBuildingIfNeeded()
        let types = waterTypeIndexBuildingIfNeeded()
        let byFormID = Dictionary(
            refs.map { ($0.formID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var volumes: [WaterVolume] = []
        for placement in owner.resolveCollisionPlacements(refs: refs) {
            guard
                let ref = byFormID[placement.reference],
                let model = attempt({ try collisionModels.model(path: placement.modelPath) })
            else { continue }
            let waterType = bases[ref.base.rawValue]?.details.waterType
            if let waterType, let water = placedWater(
                ref, model: model, transform: placement.transform,
                water: (waterType, types[waterType.rawValue])
            ) {
                volumes.append(water)
            }
            if let planes = currentPlaneVolume(ref, model: model, transform: placement.transform) {
                volumes.append(planes)
            }
        }
        return volumes
    }

    /// A water activator: the root collision shape at the reference, its surface the
    /// reference's z. The phantom's own offset in the mesh is not used.
    private func placedWater(
        _ ref: PlacedReference, model: NIFCollisionModel, transform: float4x4,
        water: (type: FormID, record: WaterType?)
    ) -> WaterVolume? {
        let (type, record) = water
        guard
            let shape = model.bodies.first?.shapes.first,
            let local = NIFCollisionModel.bounds(of: shape.geometry)
        else { return nil }
        let centre = (local.min + local.max) / 2
        return WaterVolume(
            transform: transform * shape.transform * MatrixMath.translation(centre),
            halfExtents: (local.max - local.min) / 2, surface: ref.placement.position.z,
            currents: WaterCurrentList.decode(ref.details.waterVelocities), waterType: type,
            isDangerous: record.map { $0.details.flags & 0x1 != 0 } ?? false
        )
    }

    /// One box over the model's root collision, holding a plane current per
    /// `CurrentPlane` shape. No surface: it pushes, but holds no water.
    private func currentPlaneVolume(
        _ ref: PlacedReference, model: NIFCollisionModel, transform: float4x4
    ) -> WaterVolume? {
        guard !model.currentPlanes.isEmpty, let local = model.bounds else { return nil }
        let currents = model.currentPlanes.map { plane in
            let world = transform * plane.transform
            return WaterCurrentList.plane(
                shape: world, boundRadius: plane.boundRadius * simd_length(world.columns.0),
                linear: ref.details.waterLinearVelocity,
                angular: ref.details.waterRotationalVelocity
            )
        }
        let centre = (local.min + local.max) / 2
        return WaterVolume(
            transform: transform * MatrixMath.translation(centre),
            halfExtents: (local.max - local.min) / 2, surface: nil, currents: currents
        )
    }
}
