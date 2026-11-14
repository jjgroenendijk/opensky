// The heap memory streamed textures map their tiles to. The pool grows by one placement
// heap at a time and frees a heap once all its tiles are free, so its size follows what
// the textures use. See docs/rendering/texture-streaming.md.

public import Metal

public final class SparseTilePool {
    static let heapBytes = 16 << 20

    public let device: any MTLDevice
    public let pageSize: MTLSparsePageSize
    public let tileBytes: Int
    private var heaps: [Int: any MTLHeap] = [:]
    private var ledger: SparseTileLedger
    private var nextHeapID = 0

    public init(device: any MTLDevice, pageSize: MTLSparsePageSize) {
        self.device = device
        self.pageSize = pageSize
        tileBytes = device.sparseTileSizeInBytes(sparsePageSize: pageSize)
        ledger = SparseTileLedger(tilesPerHeap: Self.heapBytes / tileBytes)
    }

    public var reservedBytes: Int {
        heaps.count * Self.heapBytes
    }

    public var usedTiles: Int {
        ledger.usedTiles
    }

    public func heap(_ id: Int) -> any MTLHeap? {
        heaps[id]
    }

    /// `count` tiles of `kind`, new heaps included; nil when a heap cannot be made. `added`
    /// gets each new heap, so the caller can make it resident.
    public func allocate(
        _ count: Int, kind: SparseTileKind, added: (any MTLHeap) -> Void
    ) -> [SparseTile]? {
        var tiles: [SparseTile] = []
        tiles.reserveCapacity(count)
        for id in ledger.takeOrder(for: kind) where tiles.count < count {
            ledger.take(from: id, count: count - tiles.count, into: &tiles)
        }
        while tiles.count < count {
            guard let id = addHeap(kind: kind, added: added) else {
                free(tiles)
                return nil
            }
            ledger.take(from: id, count: count - tiles.count, into: &tiles)
        }
        return tiles
    }

    /// Returns tiles to the pool. Returns the heaps that became empty; the caller retires
    /// them once no frame in flight can use them.
    @discardableResult
    public func free(_ tiles: [SparseTile]) -> [any MTLHeap] {
        var emptied: [any MTLHeap] = []
        for id in ledger.free(tiles) {
            if let heap = heaps.removeValue(forKey: id) {
                emptied.append(heap)
            }
        }
        return emptied
    }

    /// The nearly empty heap whose movable tiles the caller should move, or nil.
    public func heapToDrain() -> Int? {
        ledger.heapToDrain()
    }

    private func addHeap(kind: SparseTileKind, added: (any MTLHeap) -> Void) -> Int? {
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
        ledger.addHeap(id, kind: kind)
        added(heap)
        return id
    }
}
