import OpenSkyFormatsCore
@testable import OpenSkyTerrain
import Testing

struct LargeReferenceRingTests {
    private func objects(at origin: CellCoordinate) -> DistantLODBlock {
        DistantLODBlock(
            kind: .objects, level: 4, origin: origin, path: "objects", clipMask: nil
        )
    }

    @Test func distanceCountsRingsToTheNearestCellOfTheBlock() {
        func rings(_ x: Int32, _ y: Int32) -> Int64 {
            LargeReferenceRing.distance(from: .init(x: 0, y: 0), to: objects(at: .init(x: x, y: y)))
        }
        #expect(rings(0, 0) == 0)
        #expect(rings(-4, -4) == 1)
        #expect(rings(4, 0) == 4)
        #expect(rings(-8, 8) == 8)
    }

    @Test func onlyObjectBlocksInsideTheRingHideTheirLargeReferences() {
        let center = CellCoordinate(x: 0, y: 0)
        let terrain = DistantLODBlock(
            kind: .terrain, level: 4, origin: .init(x: 4, y: 0), path: "terrain", clipMask: nil
        )
        #expect(LargeReferenceRing.hidesLargeReferences(
            of: objects(at: .init(x: 4, y: 0)), center: center, radius: 5
        ))
        #expect(!LargeReferenceRing.hidesLargeReferences(
            of: objects(at: .init(x: 8, y: 0)), center: center, radius: 5
        ))
        #expect(!LargeReferenceRing.hidesLargeReferences(of: terrain, center: center, radius: 5))
    }

    @Test func segmentsRunNorthFirstThenEast() {
        let block = objects(at: .init(x: 4, y: -4))
        #expect(LargeReferenceRing.cell(ofSegment: 0, in: block) == CellCoordinate(x: 4, y: -4))
        #expect(LargeReferenceRing.cell(ofSegment: 3, in: block) == CellCoordinate(x: 4, y: -1))
        #expect(LargeReferenceRing.cell(ofSegment: 6, in: block) == CellCoordinate(x: 5, y: -2))
        #expect(LargeReferenceRing.cell(ofSegment: 16, in: block) == nil)
    }

    @Test func aSegmentHidesOnlyWhenTheRingCoversItsCell() {
        let block = objects(at: .init(x: 4, y: 0))
        func hides(_ segment: Int) -> Bool {
            LargeReferenceRing.hidesSegment(
                segment, of: block, center: .init(x: 0, y: 0), radius: 5
            )
        }
        #expect(hides(0))
        #expect(hides(7))
        #expect(!hides(8))
        #expect(!hides(15))
        #expect(hides(99))
    }

    @Test func cellsCoverTheRingAndHiddenBlocksButNotTheLoadedGrid() {
        let center = CellCoordinate(x: 0, y: 0)
        let loaded = (-2 ... 2).flatMap { x in (-2 ... 2).map { CellCoordinate(x: x, y: $0) } }
        let cells = LargeReferenceRing.cells(
            center: center, radii: (5, 2),
            hiddenCells: Set(loaded + [CellCoordinate(x: 3, y: 0)]),
            blocks: [objects(at: .init(x: 4, y: 0)), objects(at: .init(x: 12, y: 0))]
        )
        #expect(cells.contains(CellCoordinate(x: 5, y: 5)))
        #expect(cells.contains(CellCoordinate(x: 7, y: 3)))
        #expect(!cells.contains(CellCoordinate(x: 2, y: 2)))
        #expect(!cells.contains(CellCoordinate(x: 3, y: 0)))
        #expect(!cells.contains(CellCoordinate(x: 12, y: 0)))
        #expect(cells.count == 11 * 11 - 5 * 5 - 1 + 4 * 4 - 2 * 4)
    }

    @Test func aNearCellThatIsNotLoadedKeepsTheRingsLargeReferences() {
        let building = CellCoordinate(x: 2, y: 0)
        let loaded = (-2 ... 2).flatMap { x in (-2 ... 2).map { CellCoordinate(x: x, y: $0) } }
        let cells = LargeReferenceRing.cells(
            center: .init(x: 0, y: 0), radii: (5, 2),
            hiddenCells: Set(loaded).subtracting([building]), blocks: []
        )
        #expect(cells.contains(building))
        #expect(!cells.contains(CellCoordinate(x: 1, y: 0)))
    }

    @Test func aRingNoWiderThanTheLoadedGridHasNoCells() {
        let cells = LargeReferenceRing.cells(
            center: .init(x: 0, y: 0), radii: (2, 2),
            hiddenCells: [], blocks: [objects(at: .init(x: 0, y: 0))]
        )
        #expect(cells.isEmpty)
    }
}
