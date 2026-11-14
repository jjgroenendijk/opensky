// Which heap of the tile pool gives the next tiles, and which nearly empty heap to drain.
// Tiles come from the fullest heap first, so the emptiest heaps lose their tiles and can be
// freed. See docs/rendering/texture-streaming.md.

/// One tile in one heap of the pool.
nonisolated public struct SparseTile: Hashable, Sendable {
    public let heap: Int
    public let index: Int
}

/// Whether the tiles of a heap can move. Tiles of the levels a texture can drop are movable:
/// dropping those levels and reading them again puts them in another heap. Tiles of the
/// floor levels and the tail stay mapped while the texture lives, so they are pinned.
nonisolated public enum SparseTileKind: Sendable {
    case pinned
    case movable
}

/// The free tiles of each heap of the pool, as values only.
nonisolated public struct SparseTileLedger: Sendable {
    /// A heap with at most this share of its tiles in use is worth draining.
    static let drainShare = 4

    public let tilesPerHeap: Int
    private var freeTiles: [Int: [Int]] = [:]
    private var kinds: [Int: SparseTileKind] = [:]
    /// The heap being drained: it gives tiles only when no other heap of its kind can.
    public private(set) var draining: Int?

    public init(tilesPerHeap: Int) {
        self.tilesPerHeap = tilesPerHeap
    }

    public var heapCount: Int {
        kinds.count
    }

    public var usedTiles: Int {
        var used = 0
        for (id, free) in freeTiles {
            used += kinds[id] == nil ? 0 : tilesPerHeap - free.count
        }
        return used
    }

    public func usedTiles(in heap: Int) -> Int {
        tilesPerHeap - (freeTiles[heap]?.count ?? tilesPerHeap)
    }

    public mutating func addHeap(_ id: Int, kind: SparseTileKind) {
        kinds[id] = kind
        // Reversed, so `take` hands out low indexes first.
        freeTiles[id] = Array((0 ..< tilesPerHeap).reversed())
    }

    /// The heaps of `kind` with free tiles, in the order they give them: the fullest first,
    /// then the heap being drained.
    public func takeOrder(for kind: SparseTileKind) -> [Int] {
        var order: [(id: Int, free: Int)] = []
        for (id, heapKind) in kinds where heapKind == kind && id != draining {
            let free = freeTiles[id]?.count ?? 0
            if free > 0 {
                order.append((id, free))
            }
        }
        order.sort { $0.free != $1.free ? $0.free < $1.free : $0.id < $1.id }
        var ids: [Int] = []
        for entry in order {
            ids.append(entry.id)
        }
        if let draining, kinds[draining] == kind, freeTiles[draining]?.isEmpty == false {
            ids.append(draining)
        }
        return ids
    }

    /// Moves up to `count` free tiles of `heap` into `tiles`.
    public mutating func take(from heap: Int, count: Int, into tiles: inout [SparseTile]) {
        guard var free = freeTiles[heap], !free.isEmpty else { return }
        let taken = min(count, free.count)
        for index in free.suffix(taken) {
            tiles.append(SparseTile(heap: heap, index: index))
        }
        free.removeLast(taken)
        freeTiles[heap] = free
    }

    /// Returns tiles to their heaps. Returns the heaps that became empty, which leave the
    /// ledger.
    public mutating func free(_ tiles: [SparseTile]) -> [Int] {
        var touched = Set<Int>()
        for tile in tiles where kinds[tile.heap] != nil {
            freeTiles[tile.heap, default: []].append(tile.index)
            touched.insert(tile.heap)
        }
        var emptied: [Int] = []
        for id in touched.sorted() where freeTiles[id]?.count == tilesPerHeap {
            kinds[id] = nil
            freeTiles[id] = nil
            emptied.append(id)
            if draining == id {
                draining = nil
            }
        }
        return emptied
    }

    /// The movable heap to empty, or nil. One is picked when the movable tiles in use fit in
    /// at least one heap fewer than the pool holds, and the heap with the fewest tiles in
    /// use holds at most a quarter of its tiles. It stays picked until it is empty.
    public mutating func heapToDrain() -> Int? {
        if let draining, kinds[draining] != nil {
            return draining
        }
        draining = nil
        var heaps = 0
        var used = 0
        var emptiest: (id: Int, used: Int)?
        for (id, kind) in kinds where kind == .movable {
            let inUse = usedTiles(in: id)
            heaps += 1
            used += inUse
            guard let current = emptiest else {
                emptiest = (id, inUse)
                continue
            }
            if inUse < current.used || (inUse == current.used && id < current.id) {
                emptiest = (id, inUse)
            }
        }
        let needed = (used + tilesPerHeap - 1) / tilesPerHeap
        guard
            let emptiest, heaps > needed,
            emptiest.used * Self.drainShare <= tilesPerHeap
        else { return nil }
        draining = emptiest.id
        return draining
    }
}
