// Furniture seats in a cell build: each `BSFurnitureMarkerNode` marker of a FURN
// mesh, placed in the world with the `FNMK` keyword of the record's marker of the
// same index. See docs/engine/package-schedules.md, "Furniture".

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
        let keywords = Dictionary(
            base.details.furnitureMarkers.compactMap { marker in
                marker.index.flatMap { index in marker.keyword.map { (Int(index), $0) } }
            },
            uniquingKeysWith: { first, _ in first }
        )
        return markers.enumerated().map { index, marker in
            let world = transform * SIMD4(marker.offset, 1)
            return FurnitureSeat(
                position: SIMD3(world.x, world.y, world.z),
                heading: ref.placement.rotation.z + marker.heading,
                animationType: marker.animationType,
                keyword: keywords[index],
                entryPoints: marker.entryPoints
            )
        }
    }
}
