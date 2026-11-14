// The journal's newest entries from one sequence on, read back from the newest
// entry, before and after the ring wraps.

@testable import OpenSkyFormatsCore
import OpenSkyFormatsESM
@testable import OpenSkyWorldState
import Testing

struct WorldStateJournalSinceTests {
    private static func record(_ count: Int, into journal: inout WorldStateJournal) {
        for index in 0 ..< count {
            journal.record(
                key: .plugin(name: "skyrim.esm", objectID: UInt32(0x200 + index)),
                kind: .enableState,
                change: (old: nil, new: nil),
                cell: nil
            )
        }
    }

    @Test func entriesSinceASequenceMatchAFilterOfTheWholeWindow() {
        var journal = WorldStateJournal(capacity: 4)
        Self.record(3, into: &journal)
        #expect(journal.entries(since: 2).map(\.sequence) == [2, 3])
        #expect(journal.entries(since: 1).map(\.sequence) == [1, 2, 3])
        #expect(journal.entries(since: 4).isEmpty)

        // After the ring wraps, the oldest entries are gone and the rest stay in order.
        Self.record(4, into: &journal)
        for since in UInt64(0) ... 8 {
            let expected = journal.entries.filter { $0.sequence >= since }.map(\.sequence)
            #expect(journal.entries(since: since).map(\.sequence) == expected)
        }
        #expect(journal.entries(since: 0).map(\.sequence) == [4, 5, 6, 7])
    }
}
