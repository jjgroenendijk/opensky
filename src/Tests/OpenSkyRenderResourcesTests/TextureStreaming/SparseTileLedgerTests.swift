// Which heap gives the next tiles, and which nearly empty heap the pool drains.

import OpenSkyRenderResources
import Testing

struct SparseTileLedgerTests {
    /// A ledger with one heap per entry of `used`, each with that many tiles taken.
    private func ledger(
        used: [Int], kind: SparseTileKind = .movable, tilesPerHeap: Int = 8
    ) -> (ledger: SparseTileLedger, tiles: [[SparseTile]]) {
        var ledger = SparseTileLedger(tilesPerHeap: tilesPerHeap)
        var tiles: [[SparseTile]] = []
        for (id, count) in used.enumerated() {
            ledger.addHeap(id, kind: kind)
            var taken: [SparseTile] = []
            ledger.take(from: id, count: count, into: &taken)
            tiles.append(taken)
        }
        return (ledger, tiles)
    }

    @Test func theFullestHeapGivesTilesFirst() {
        let order = ledger(used: [2, 6, 4]).ledger.takeOrder(for: .movable)
        #expect(order == [1, 2, 0])
    }

    @Test func aFullHeapAndAHeapOfTheOtherKindGiveNone() {
        var setup = ledger(used: [8, 3])
        setup.ledger.addHeap(2, kind: .pinned)
        #expect(setup.ledger.takeOrder(for: .movable) == [1])
        #expect(setup.ledger.takeOrder(for: .pinned) == [2])
    }

    @Test func takeHandsOutLowIndexesFirst() {
        let tiles = ledger(used: [3]).tiles[0]
        #expect(Set(tiles.map(\.index)) == [0, 1, 2])
    }

    @Test func aNearlyEmptyHeapIsDrainedWhenTheOthersHoldItsTiles() {
        // 5 + 6 + 1 tiles in use fit in 2 heaps of 8; the heap with 1 holds an eighth.
        var setup = ledger(used: [5, 6, 1])
        let drained = setup.ledger.heapToDrain()
        #expect(drained == 2)
        #expect(setup.ledger.takeOrder(for: .movable) == [1, 0, 2])
    }

    @Test func noHeapIsDrainedWhenTheTilesNeedEveryHeap() {
        // 8 + 8 + 1 tiles need all 3 heaps of 8, though the third holds only an eighth.
        var setup = ledger(used: [8, 8, 1])
        let drained = setup.ledger.heapToDrain()
        #expect(drained == nil)
    }

    @Test func onlyAHeapAtMostAQuarterFullIsDrained() {
        // 3 of 8 tiles is more than a quarter, though 1 + 3 fit in one heap.
        var setup = ledger(used: [1, 3])
        let emptier = setup.ledger.heapToDrain()
        #expect(emptier == 0)
        var fuller = ledger(used: [3, 3])
        let drained = fuller.ledger.heapToDrain()
        #expect(drained == nil)
    }

    @Test func pinnedHeapsAreNeverDrained() {
        var setup = ledger(used: [1, 1], kind: .pinned)
        let drained = setup.ledger.heapToDrain()
        #expect(drained == nil)
    }

    @Test func theDrainedHeapStaysPickedUntilItIsEmptyThenLeaves() {
        var setup = ledger(used: [5, 1])
        let first = setup.ledger.heapToDrain()
        let fullEmptied = setup.ledger.free(setup.tiles[0])
        let second = setup.ledger.heapToDrain()
        let emptied = setup.ledger.free(setup.tiles[1])
        #expect(first == 1)
        #expect(fullEmptied == [0])
        #expect(second == 1)
        #expect(emptied == [1])
        #expect(setup.ledger.draining == nil)
        #expect(setup.ledger.heapCount == 0)
        #expect(setup.ledger.usedTiles == 0)
    }

    @Test func usedTilesCountsEveryHeap() {
        let setup = ledger(used: [5, 1, 0])
        #expect(setup.ledger.usedTiles == 6)
        #expect(setup.ledger.usedTiles(in: 0) == 5)
    }
}
