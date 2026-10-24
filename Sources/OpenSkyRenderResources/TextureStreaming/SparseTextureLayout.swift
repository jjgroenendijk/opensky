// How the levels of one placement-sparse texture map to heap tiles. Levels below
// `firstLevelInTail` map tile by tile; the small levels share one packed tail.
// See docs/rendering/texture-streaming.md.

nonisolated public struct SparseTextureLayout: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let mipCount: Int
    /// One tile's size in texels.
    public let tileSize: SIMD2<Int>
    public let firstLevelInTail: Int
    public let tailTiles: Int

    public init(
        size: SIMD2<Int>, mipCount: Int, tileSize: SIMD2<Int>,
        tail: (firstLevel: Int, tiles: Int)
    ) {
        width = size.x
        height = size.y
        self.mipCount = mipCount
        self.tileSize = SIMD2(max(tileSize.x, 1), max(tileSize.y, 1))
        firstLevelInTail = min(max(tail.firstLevel, 0), mipCount)
        tailTiles = max(tail.tiles, 0)
    }

    /// The tile grid of a level above the tail.
    public func tileGrid(level: Int) -> SIMD2<Int> {
        let levelWidth = max(1, width >> level)
        let levelHeight = max(1, height >> level)
        return SIMD2(
            (levelWidth + tileSize.x - 1) / tileSize.x,
            (levelHeight + tileSize.y - 1) / tileSize.y
        )
    }

    public func tiles(level: Int) -> Int {
        guard level < firstLevelInTail else { return 0 }
        let grid = tileGrid(level: level)
        return grid.x * grid.y
    }

    /// Tiles that keep `level` and every smaller level resident, tail included.
    public func tiles(fromLevel level: Int) -> Int {
        let first = min(max(level, 0), firstLevelInTail)
        return (first ..< firstLevelInTail).reduce(tailTiles) { $0 + tiles(level: $1) }
    }

    /// The smallest level the texture can drop to: the tail stays mapped.
    public var floorLevel: Int {
        min(firstLevelInTail, mipCount - 1)
    }

    /// The first level no larger than `size` texels on its long side, never below the floor.
    public func level(fittingWithin size: Int) -> Int {
        var level = 0
        while level < floorLevel, max(width >> level, height >> level) > size {
            level += 1
        }
        return level
    }
}
