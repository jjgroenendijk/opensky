// Lock natives of `ObjectReference`: `Lock`, `SetLockLevel`, and the reads write and
// read the same `ReferenceLockState` the use-key gate checks.

import Foundation
import OpenSkyInventoryInterface
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusNativeLockTests {
    @Test func aReferenceWithoutXLOCReadsUnlocked() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        #expect(fixture.call("IsLocked", returnType: .boolean) == .returned(.boolean(false)))
        #expect(fixture.call("GetLockLevel", returnType: .integer) == .returned(.integer(0)))
        #expect(fixture.call("GetKey", returnType: .object("Key")) == .returned(.none))
    }

    @Test func lockWritesTheStateTheGateReads() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        #expect(fixture.call("Lock") == .returned(.none))
        #expect(fixture.session.worldState.component(ReferenceLockState.self, for: fixture.key)
            == ReferenceLockState(isLocked: true, level: 1, key: nil))
        #expect(fixture.call("IsLocked", returnType: .boolean) == .returned(.boolean(true)))
        #expect(fixture.call("Lock", arguments: [.boolean(false)]) == .returned(.none))
        #expect(fixture.call("IsLocked", returnType: .boolean) == .returned(.boolean(false)))
    }

    @Test func setLockLevelKeepsTheLockedFlag() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        _ = fixture.call("Lock")
        #expect(fixture.call("SetLockLevel", arguments: [.integer(75)]) == .returned(.none))
        #expect(fixture.call("GetLockLevel", returnType: .integer) == .returned(.integer(75)))
        #expect(fixture.call("IsLocked", returnType: .boolean) == .returned(.boolean(true)))
        #expect(fixture.call("SetLockLevel", arguments: [.integer(900)]) == .returned(.none))
        #expect(fixture.call("GetLockLevel", returnType: .integer) == .returned(.integer(255)))
    }
}
