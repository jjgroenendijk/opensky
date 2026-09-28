// `Actor.ShowBarterMenu` (issue #506): the native a merchant's dialogue
// fragment calls, over a stand-in session closure.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import FormatsTestSupport
import Foundation
@testable import OpenSky
@testable import OpenSkyFormats
import Testing

@MainActor
struct PapyrusNativeBarterTests {
    @Test func showBarterMenuOpensThroughTheSessionOrSaysWhyNot() throws {
        let entry = try PapyrusWorldFixture.actorEntry(
            objectID: 0x0004_0001,
            base: 0x0004_0002,
            scripts: [VMADFixture.Script("Merchant", properties: [])]
        )
        let session = PapyrusWorldFixture.session(
            objects: [PapyrusWorldFixture.eventScript("Merchant", events: [])],
            entries: [entry]
        )
        PapyrusWorldFixture.drain(session.world)
        let registry = PapyrusWorldFixture.registry(for: session)
        let merchant = try #require(session.bridge.objectHandle(for: entry.key))
        let show = {
            registry.invoke(PapyrusWorldFixture.methodCall(
                "Actor", "ShowBarterMenu", receiver: merchant, arguments: [], returnType: .none
            ))
        }

        guard case .failed = show() else {
            Issue.record("a session with no vendor data must refuse")
            return
        }

        var asked: [ReferenceKey] = []
        session.bridge.showBarterMenu = { actor in
            asked.append(actor)
            return (asked.count == 1, asked.count == 1 ? "opened" : "not a merchant")
        }
        #expect(show() == .returned(.none))
        #expect(asked == [entry.key])
        guard case .failed = show() else {
            Issue.record("a refused barter must fail with its reason")
            return
        }
    }
}
