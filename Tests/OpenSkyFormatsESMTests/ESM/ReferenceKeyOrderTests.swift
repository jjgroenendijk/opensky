@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct ReferenceKeyOrderTests {
    private struct Member: Equatable {
        let key: ReferenceKey
        let value: Int
    }

    private static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: objectID)
    }

    @Test func sortsByKeyAndKeepsTheNewValuesOfUnchangedMembers() {
        var order = ReferenceKeyOrder()
        let first = [Member(key: .player, value: 0), Member(key: Self.key(2), value: 1)]
        #expect(order.sorted(first, by: \.key).map(\.key) == [Self.key(2), .player])

        let moved = [Member(key: .player, value: 5), Member(key: Self.key(2), value: 6)]
        #expect(order.sorted(moved, by: \.key).map(\.value) == [6, 5])
    }

    @Test func sortsAgainWhenTheMembersChange() {
        var order = ReferenceKeyOrder()
        _ = order.sorted([Self.key(3), Self.key(1)], by: { $0 })

        #expect(order.sorted([Self.key(4), Self.key(1), Self.key(2)], by: { $0 })
            == [Self.key(1), Self.key(2), Self.key(4)])
    }

    @Test func ascendingLeavesAnOrderedListAndSortsAnUnorderedOne() {
        let ordered = [Self.key(1), Self.key(2), .player]
        #expect(ReferenceKeyOrder.ascending(ordered, by: { $0 }) == ordered)
        #expect(ReferenceKeyOrder.ascending(ordered.reversed(), by: { $0 }) == ordered)
    }
}
