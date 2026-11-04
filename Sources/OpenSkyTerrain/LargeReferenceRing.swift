// The cells whose large references draw their full model, from `uLargeRefLODGridSize`
// (docs/engine/distant-lod.md, "Large references").

import OpenSkyFormatsCore

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

    /// The ring's cells, plus every cell of an object block it hides shapes from, so no
    /// large reference of that block goes missing. The loaded grid draws its own.
    public static func cells(
        center: CellCoordinate,
        radius: Int32,
        loadedRadius: Int32,
        hiddenCells: Set<CellCoordinate>,
        blocks: [DistantLODBlock]
    ) -> Set<CellCoordinate> {
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
