// Furniture seats in a cell build: each `BSFurnitureMarkerNode` marker of a FURN
// mesh, placed in the world with the `FNMK` keyword and the `NAM0` disabled entries
// of the record's marker of the same index, switched by `MNAM`, with the record's
// flags. See docs/engine/furniture.md.

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
        let rules = base.furnitureRules
        return markers.enumerated().map { index, marker in
            let world = transform * SIMD4(marker.offset, 1)
            let root = transform * SIMD4(marker.offset.x, marker.offset.y, 0, 1)
            let disabled = records[index]?.disabledEntryPoints ?? 0
            var seat = FurnitureSeat(
                position: SIMD3(world.x, world.y, world.z),
                heading: ref.placement.rotation.z + marker.heading,
                animationType: marker.animationType,
                keyword: records[index]?.keyword,
                entryPoints: marker.entryPoints & ~disabled,
                isEnabled: base.usesFurnitureMarker(index),
                root: SIMD3(root.x, root.y, root.z)
            )
            seat.rules = rules
            return seat
        }
    }
}

nonisolated extension ModelBase {
    /// Flag bits: UESP "Skyrim Mod:Mod File Format/FURN" and the Creation Kit wiki "Furniture".
    var furnitureRules: FurnitureRules {
        FurnitureRules(
            childCanUse: headerFlags & 0x2000_0000 != 0,
            mustExitToTalk: headerFlags & 0x1000_0000 != 0,
            isPerch: (furnitureFlags ?? 0) & 0x0400_0000 != 0,
            ignoredBySandbox: (details.flags ?? 0) & 0x02 != 0,
            associatedSpell: details.associatedSpell
        )
    }
}
