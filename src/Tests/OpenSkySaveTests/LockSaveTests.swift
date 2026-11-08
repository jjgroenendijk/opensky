// LOCK chunk: a picked or relocked lock in the native save comes back as it was,
// and a session that changed no lock writes no chunk.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventoryInterface
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct LockSaveTests {
    private let chest = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_2345)
    private let state = ReferenceLockState(
        isLocked: false, level: 50, key: FormID(0x0003_A0F2)
    )

    private func snapshot(_ lock: ReferenceLockState) -> WorldStateSnapshot {
        OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: chest,
                    cell: OpenSkySaveFixture.whiterun,
                    components: [lock.erased]
                )
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
    }

    @Test func anUnlockedChestSurvivesAnEncodeAndDecode() throws {
        let original = snapshot(state)
        let data = OpenSkySaveFixture.encode(original)
        #expect(data.range(of: Data("LOCK".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        #expect(store.component(ReferenceLockState.self, for: chest) == state)
    }

    @Test func aLockWithNoKeyKeepsNoKey() throws {
        let keyless = ReferenceLockState(isLocked: true, level: 255, key: nil)
        let file = try OpenSkySaveDecoder.decode(OpenSkySaveFixture.encode(snapshot(keyless)))
        #expect(file.snapshot[chest]?.component(ReferenceLockState.self) == keyless)
    }

    @Test func noLockChangeWritesNoChunk() {
        let data = OpenSkySaveFixture.encode(
            OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood)
        )
        #expect(data.range(of: Data("LOCK".utf8)) == nil)
    }
}
