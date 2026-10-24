// Furniture seats in a cell build: each `BSFurnitureMarkerNode` marker of a FURN
// mesh, placed in the world with the `FNMK` keyword and the `NAM0` disabled entries
// of the record's marker of the same index, and switched by `MNAM`. See
// docs/engine/furniture.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyRendering
import OpenSkyWorldInterface
import simd

nonisolated extension CellSceneBuilder {
    /// The seats of one furniture reference, in marker order.
    func seats(of base: ModelBase, at ref: PlacedReference) -> [FurnitureSeat] {
        guard let modelPath = base.modelPath else { return [] }
        let markers = meshes.furnitureMarkers(forPath: modelPath)
        guard !markers.isEmpty else { return [] }
        let transform = MatrixMath.placement(
            position: ref.placement.position, rotation: ref.placement.rotation, scale: ref.scale
        )
        let records = Dictionary(
            base.details.furnitureMarkers.compactMap { marker in
                marker.index.map { (Int($0), marker) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        return markers.enumerated().map { index, marker in
            let world = transform * SIMD4(marker.offset, 1)
            let root = transform * SIMD4(marker.offset.x, marker.offset.y, 0, 1)
            let disabled = records[index]?.disabledEntryPoints ?? 0
            return FurnitureSeat(
                position: SIMD3(world.x, world.y, world.z),
                heading: ref.placement.rotation.z + marker.heading,
                animationType: marker.animationType,
                keyword: records[index]?.keyword,
                entryPoints: marker.entryPoints & ~disabled,
                isEnabled: base.usesFurnitureMarker(index),
                root: SIMD3(root.x, root.y, root.z)
            )
        }
    }
}
