// The trap census natives: trigger occupancy, linked chains, the base object, and
// the traced stubs that answer an empty value instead of stopping a script.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyPhysics
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeTrapTests {
    private typealias Fixture = PapyrusNativeReferenceFixture

    @Test func triggerObjectCountFollowsEnterAndLeave() throws {
        let fixture = try Fixture.make()
        let count = { fixture.call("GetTriggerObjectCount", returnType: .integer) }
        #expect(count() == .returned(.integer(0)))
        fixture.session.bridge.handleTriggerTransition(
            TriggerTransitionEvent(reference: fixture.key, phase: .enter)
        )
        #expect(count() == .returned(.integer(1)))
        fixture.session.bridge.handleTriggerTransition(
            TriggerTransitionEvent(reference: fixture.key, phase: .leave)
        )
        #expect(count() == .returned(.integer(0)))
    }

    @Test func nthLinkedRefFollowsTheUntaggedChain() throws {
        let fixture = try Fixture.make(links: [(keyword: nil, ref: Fixture.leverID)])
        let first = fixture.call(
            "GetNthLinkedRef", arguments: [.integer(1)], returnType: .object("ObjectReference")
        )
        #expect(first == .returned(.object(fixture.receiver)))
        let third = fixture.call(
            "GetNthLinkedRef", arguments: [.integer(3)], returnType: .object("ObjectReference")
        )
        #expect(third == .returned(.object(fixture.receiver)))
        let none = fixture.call(
            "GetNthLinkedRef", arguments: [.integer(0)], returnType: .object("ObjectReference")
        )
        #expect(none == .returned(.none))
    }

    @Test func baseObjectIsAHandle() throws {
        let fixture = try Fixture.make()
        let base = fixture.call("GetBaseObject", returnType: .object("Form"))
        guard case let .returned(.object(handle)) = base else {
            Issue.record("GetBaseObject did not return an object: \(base)")
            return
        }
        #expect(fixture.session.world.referenceKey(for: handle)
            == .plugin(name: PapyrusWorldFixture.pluginName, objectID: 0x100))
    }

    @Test func stubsAnswerAnEmptyValueAndCountAsStubbed() throws {
        let fixture = try Fixture.make()
        #expect(fixture.call("ApplyHavokImpulse") == .deviated(.none, .stubbed))
        #expect(fixture.call("IsLockBroken", returnType: .boolean) == .returned(.boolean(false)))
    }

    @Test func processTrapHitNeedsAnActor() throws {
        let fixture = try Fixture.make()
        let result = fixture.call(
            "ProcessTrapHit", arguments: [.object(fixture.receiver), .float(10)]
        )
        guard case .failed = result else {
            Issue.record("ProcessTrapHit on a lever should fail: \(result)")
            return
        }
    }
}
