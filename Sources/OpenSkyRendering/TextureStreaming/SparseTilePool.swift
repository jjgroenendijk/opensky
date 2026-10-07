// The heap memory streamed textures map their tiles to. The pool grows by one placement
// heap at a time and frees a heap once all its tiles are free, so its size follows what
// the textures use. See docs/rendering/texture-streaming.md.

import Metal

/// One tile in one heap of the pool.
struct SparseTile: Hashable {
    let heap: Int
    let index: Int
}

final class SparseTilePool {
    static let heapBytes = 16 << 20

    let device: MTLDevice
    let pageSize: MTLSparsePageSize
    let tileBytes: Int
    private var heaps: [Int: MTLHeap] = [:]
    private var freeTiles: [Int: [Int]] = [:]
    private var nextHeapID = 0

    init(device: MTLDevice, pageSize: MTLSparsePageSize) {
        self.device = device
        self.pageSize = pageSize
        tileBytes = device.sparseTileSizeInBytes(sparsePageSize: pageSize)
    }

    var tilesPerHeap: Int {
        Self.heapBytes / tileBytes
    }

    var reservedBytes: Int {
        heaps.count * Self.heapBytes
    }

    var usedTiles: Int {
        heaps.keys.reduce(0) { $0 + tilesPerHeap - (freeTiles[$1]?.count ?? 0) }
    }

    func heap(_ id: Int) -> MTLHeap? {
        heaps[id]
    }

    /// `count` tiles, new heaps included; nil when a heap cannot be made. `added` gets
    /// each new heap, so the caller can make it resident.
    func allocate(_ count: Int, added: (MTLHeap) -> Void) -> [SparseTile]? {
        var tiles: [SparseTile] = []
        tiles.reserveCapacity(count)
        for id in heaps.keys.sorted() where tiles.count < count {
            take(from: id, count: count - tiles.count, into: &tiles)
        }
        while tiles.count < count {
            guard let id = addHeap(added: added) else {
                free(tiles)
                return nil
            }
            take(from: id, count: count - tiles.count, into: &tiles)
        }
        return tiles
    }

    /// Returns tiles to the pool. Returns the heaps that became empty; the caller retires
    /// them once no frame in flight can use them.
    @discardableResult
    func free(_ tiles: [SparseTile]) -> [MTLHeap] {
        for tile in tiles {
            freeTiles[tile.heap, default: []].append(tile.index)
        }
        var emptied: [MTLHeap] = []
        for id in Set(tiles.map(\.heap)) where freeTiles[id]?.count == tilesPerHeap {
            if let heap = heaps.removeValue(forKey: id) {
                emptied.append(heap)
            }
            freeTiles[id] = nil
        }
        return emptied
    }

    private func take(from id: Int, count: Int, into tiles: inout [SparseTile]) {
        guard var free = freeTiles[id], !free.isEmpty else { return }
        let taken = min(count, free.count)
        for index in free.suffix(taken) {
            tiles.append(SparseTile(heap: id, index: index))
        }
        free.removeLast(taken)
        freeTiles[id] = free
    }

    private func addHeap(added: (MTLHeap) -> Void) -> Int? {
        let descriptor = MTLHeapDescriptor()
        descriptor.type = .placement
        descriptor.storageMode = .private
        descriptor.size = Self.heapBytes
        descriptor.maxCompatiblePlacementSparsePageSize = pageSize
        guard let heap = device.makeHeap(descriptor: descriptor) else { return nil }
        heap.label = "Streamed texture tiles"
        let id = nextHeapID
        nextHeapID += 1
        heaps[id] = heap
        // Reversed, so `take` hands out low indexes first.
        freeTiles[id] = Array((0 ..< tilesPerHeap).reversed())
        added(heap)
        return id
    }
}
