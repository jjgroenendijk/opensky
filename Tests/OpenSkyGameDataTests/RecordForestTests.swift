// The parent and previous-sibling tree rebuild, with its broken-link and
// cycle counts. See docs/formats/idle.md.

import Foundation
@testable import OpenSkyGameData
import Testing

struct RecordForestTests {
    private typealias Link = RecordForest<Int>.Link

    @Test func ordersSiblingsByTheirPreviousSiblingChain() {
        let forest = RecordForest([
            Link(id: 1, parent: nil, previousSibling: nil),
            Link(id: 4, parent: 1, previousSibling: 3),
            Link(id: 2, parent: 1, previousSibling: nil),
            Link(id: 3, parent: 1, previousSibling: 2),
            Link(id: 5, parent: 4, previousSibling: nil)
        ])
        #expect(forest.roots == [1])
        #expect(forest.children(of: 1) == [2, 3, 4])
        #expect(forest.path(to: 5) == [1, 4, 5])
        #expect(forest.maximumDepth == 3)
        #expect(forest.brokenSiblingChains == 0)
        #expect(forest.unreachable.isEmpty)
    }

    @Test func keepsOrphansAsRootsAndCountsBrokenChains() {
        let forest = RecordForest([
            Link(id: 1, parent: 99, previousSibling: nil),
            Link(id: 2, parent: nil, previousSibling: nil),
            Link(id: 3, parent: nil, previousSibling: nil),
            Link(id: 4, parent: 2, previousSibling: nil),
            Link(id: 5, parent: 2, previousSibling: nil)
        ])
        #expect(forest.orphans == [1])
        #expect(forest.roots == [1, 2, 3])
        #expect(forest.children(of: 2) == [4, 5])
        #expect(forest.brokenSiblingChains == 1, "only the child group of 2 counts")
    }

    @Test func parentCycleIsUnreachableAndNeverLoops() {
        let forest = RecordForest([
            Link(id: 1, parent: 2, previousSibling: nil),
            Link(id: 2, parent: 1, previousSibling: nil),
            Link(id: 3, parent: nil, previousSibling: 3)
        ])
        #expect(forest.roots == [3])
        #expect(Set(forest.unreachable) == [1, 2])
        #expect(forest.path(to: 1) == [2, 1])
        #expect(forest.maximumDepth == 1)
    }

    @Test func siblingLoopKeepsInputOrder() {
        let forest = RecordForest([
            Link(id: 1, parent: nil, previousSibling: nil),
            Link(id: 2, parent: 1, previousSibling: 3),
            Link(id: 3, parent: 1, previousSibling: 2)
        ])
        #expect(forest.children(of: 1) == [2, 3])
        #expect(forest.brokenSiblingChains == 1)
    }
}
