// The cells whose large references draw their full model, from `uLargeRefLODGridSize`
// (docs/engine/distant-lod.md, "Large references").

public import OpenSkyFormatsCore

nonisolated public enum LargeReferenceRing {
    /// The fewest rings between `center` and any cell of the block.
    public static func distance(from center: CellCoordinate, to block: DistantLODBlock) -> Int64 {
        func axis(_ value: Int32, _ lower: Int32, _ count: Int32) -> Int64 {
            let low = Int64(lower)
            let high = low + Int64(count) - 1
            return max(low - Int64(value), 0, Int64(value) - high)
        }
        return max(
            axis(center.x, block.origin.x, block.level),
            axis(center.y, block.origin.y, block.level)
        )
    }

    /// An object block whose large-reference shapes the ring replaces.
    public static func hidesLargeReferences(
        of block: DistantLODBlock,
        center: CellCoordinate,
        radius: Int32
    ) -> Bool {
        block.kind == .objects && distance(from: center, to: block) <= Int64(radius)
    }

    /// The cell segment `segment` of a block's large-reference shape holds. The segments
    /// run north first, then east (docs/formats/lod.md, "Large references").
    static func cell(ofSegment segment: Int, in block: DistantLODBlock) -> CellCoordinate? {
        let level = Int(block.level)
        guard segment >= 0, segment < level * level else { return nil }
        return CellCoordinate(
            x: block.origin.x + Int32(segment / level),
            y: block.origin.y + Int32(segment % level)
        )
    }

    /// A segment whose cell the ring draws with full models. A segment past the block's
    /// cells follows the whole block.
    static func hidesSegment(
        _ segment: Int,
        of block: DistantLODBlock,
        center: CellCoordinate,
        radius: Int32
    ) -> Bool {
        guard let cell = cell(ofSegment: segment, in: block) else {
            return hidesLargeReferences(of: block, center: center, radius: radius)
        }
        let rings = max(
            abs(Int64(cell.x) - Int64(center.x)), abs(Int64(cell.y) - Int64(center.y))
        )
        return block.kind == .objects && rings <= Int64(radius)
    }

    /// The ring's cells, plus every cell of each block in `blocks` whose large-reference
    /// shape hides whole, so no large reference of it goes missing. The loaded grid draws
    /// its own.
    public static func cells(
        center: CellCoordinate,
        radii: (radius: Int32, loadedRadius: Int32),
        hiddenCells: Set<CellCoordinate>,
        blocks: [DistantLODBlock]
    ) -> Set<CellCoordinate> {
        let (radius, loadedRadius) = radii
        var cells: Set<CellCoordinate> = []
        guard radius > loadedRadius else { return cells }
        func add(x: Int32, y: Int32) {
            let cell = CellCoordinate(x: x, y: y)
            let rings = max(abs(Int64(x) - Int64(center.x)), abs(Int64(y) - Int64(center.y)))
            if rings > Int64(loadedRadius), !hiddenCells.contains(cell) {
                cells.insert(cell)
            }
        }
        for x in center.x - radius ... center.x + radius {
            for y in center.y - radius ... center.y + radius {
                add(x: x, y: y)
            }
        }
        for block in blocks
            where hidesLargeReferences(of: block, center: center, radius: radius)
        {
            for x in block.origin.x ..< block.origin.x + block.level {
                for y in block.origin.y ..< block.origin.y + block.level {
                    add(x: x, y: y)
                }
            }
        }
        return cells
    }
}
