// Per-kind store revisions and the cache that keys on them.

@testable import OpenSkyFormatsESM
@testable import OpenSkyWorldState
import Testing

@MainActor
struct WorldStateRevisionTests {
    private let door = ReferenceKey.plugin(name: "test.esm", objectID: 0x10)

    @Test func aWriteMovesOnlyTheRevisionOfItsKind() {
        let store = WorldStateStore()
        let enable = store.revision(of: [.enableState])
        let transform = store.revision(of: [.transform])

        store.set(ReferenceEnableState.disabled, for: door)

        #expect(store.revision(of: [.enableState]) != enable)
        #expect(store.revision(of: [.transform]) == transform)
        #expect(store.revision(of: [.transform, .enableState]) != enable &+ transform)
    }

    @Test func anEqualWriteKeepsTheRevision() {
        let store = WorldStateStore()
        store.set(ReferenceEnableState.disabled, for: door)
        let before = store.revision(of: [.enableState])

        store.set(ReferenceEnableState.disabled, for: door)

        #expect(store.revision(of: [.enableState]) == before)
    }

    @Test func aResetAndARestoreMoveTheRevision() {
        let store = WorldStateStore()
        store.set(ReferenceEnableState.disabled, for: door)
        let snapshot = store.snapshot()
        let written = store.revision(of: [.enableState])

        store.reset(.enableState, for: door)
        let reset = store.revision(of: [.enableState])
        let transform = store.revision(of: [.transform])
        store.restore(from: snapshot)

        #expect(reset != written)
        #expect(store.revision(of: [.enableState]) != reset)
        #expect(store.revision(of: [.transform]) != transform)
    }

    @Test func theCacheBuildsAgainOnlyForANewKey() {
        let cache = RevisionCache<Int, String>()
        var builds = 0
        func read(_ key: Int) -> String {
            cache.value(for: key) {
                builds += 1
                return "built \(key)"
            }
        }

        #expect(read(1) == "built 1")
        #expect(read(1) == "built 1")
        #expect(read(2) == "built 2")
        #expect(builds == 2)
    }
}
