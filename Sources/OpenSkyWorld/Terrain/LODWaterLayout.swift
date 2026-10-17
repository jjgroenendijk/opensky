// Where distant water goes: the LOD area of the worldspace, less a hole over the
// loaded cells, which draw their own water. At most four rectangles.

import OpenSkyFormatsCore

nonisolated public enum LODWaterLayout {
    /// A block of cells: the south-west cell and the size in cells.
    public struct Rectangle: Equatable, Sendable {
        public let origin: CellCoordinate
        public let width: Int32
        public let height: Int32

        public init(origin: CellCoordinate, width: Int32, height: Int32) {
            self.origin = origin
            self.width = width
            self.height = height
        }
    }

    /// `area` is the whole LOD area; the hole is the bounding box of `hidden` inside it.
    public static func rectangles(area: Rectangle, hidden: Set<CellCoordinate>) -> [Rectangle] {
        let minX = area.origin.x, minY = area.origin.y
        let maxX = minX + area.width, maxY = minY + area.height
        let inside = hidden.filter {
            (minX ..< maxX).contains($0.x) && (minY ..< maxY).contains($0.y)
        }
        guard
            let holeMinX = inside.map(\.x).min(), let holeMaxX = inside.map(\.x).max(),
            let holeMinY = inside.map(\.y).min(), let holeMaxY = inside.map(\.y).max()
        else { return area.width > 0 && area.height > 0 ? [area] : [] }
        let holeEndX = holeMaxX + 1, holeEndY = holeMaxY + 1
        let strips = [
            Rectangle(origin: area.origin, width: area.width, height: holeMinY - minY),
            Rectangle(
                origin: CellCoordinate(x: minX, y: holeEndY), width: area.width,
                height: maxY - holeEndY
            ),
            Rectangle(
                origin: CellCoordinate(x: minX, y: holeMinY), width: holeMinX - minX,
                height: holeEndY - holeMinY
            ),
            Rectangle(
                origin: CellCoordinate(x: holeEndX, y: holeMinY), width: maxX - holeEndX,
                height: holeEndY - holeMinY
            )
        ]
        return strips.filter { $0.width > 0 && $0.height > 0 }
    }
}
