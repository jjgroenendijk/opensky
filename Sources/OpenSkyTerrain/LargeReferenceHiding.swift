// What one distant LOD build hid for the large-reference ring
// (docs/engine/distant-lod.md, "Large references").

import OpenSkyFormatsCore
import OpenSkyRendering

nonisolated struct LargeReferenceHiding {
    let center: CellCoordinate
    let radius: Int32
    /// Blocks whose large-reference shape has no segments and so hid whole.
    private(set) var wholeBlocks: [DistantLODBlock] = []
    private(set) var hiddenSegments = 0

    /// `model` without the large-reference cells the ring draws with full models.
    mutating func hiding(_ model: RenderModel, of block: DistantLODBlock) -> RenderModel {
        if model.hasUnsegmentedLargeReferences {
            wholeBlocks.append(block)
        }
        var hidden: Set<Int> = []
        let kept = model.withoutLargeReferences { segment in
            let hides = LargeReferenceRing.hidesSegment(
                segment, of: block, center: center, radius: radius
            )
            if hides {
                hidden.insert(segment)
            }
            return hides
        }
        hiddenSegments += hidden.count
        return kept
    }
}
