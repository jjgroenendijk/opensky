// `GetLinkedRef` and `Activate` (issue #172), plus the headless policy the
// whole `ObjectReference` family shares. Satellite of
// `PapyrusNativeObjectReferenceTests`.

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusNativeObjectReferenceLinkTests {
    private typealias Fixture = PapyrusNativeReferenceFixture

    @Test func getLinkedRefResolvesUntaggedAndTaggedLinks() throws {
        let fixture = try Fixture.make(links: [
            (keyword: Fixture.keywordID, ref: Fixture.doorID),
            (keyword: nil, ref: Fixture.leverID)
        ])
        let untagged = fixture.call("GetLinkedRef", returnType: .object("ObjectReference"))
        guard case let .returned(.object(handle)) = untagged else {
            Issue.record("GetLinkedRef() did not return an object: \(untagged)")
            return
        }
        #expect(fixture.session.world.referenceKey(for: handle)
            == Fixture.key(Fixture.leverID))

        let tagged = fixture.call(
            "GetLinkedRef",
            arguments: [.object(fixture.handle(Fixture.keywordID))],
            returnType: .object("ObjectReference")
        )
        guard case let .returned(.object(linked)) = tagged else {
            Issue.record("GetLinkedRef(keyword) did not return an object: \(tagged)")
            return
        }
        #expect(fixture.session.world.referenceKey(for: linked)
            == Fixture.key(Fixture.doorID))
    }

    /// Every "no link" case is Papyrus `None`, which is `PapyrusValue.none` —
    /// the same value the interpreter writes for an object-returning call that
    /// failed, so a script sees one representation of nothing.
    @Test func getLinkedRefReturnsNoneWhenNothingMatches() throws {
        #expect(PapyrusType.object("ObjectReference").defaultValue == .none)

        let empty = try Fixture.make()
        #expect(empty.call(
            "GetLinkedRef", returnType: .object("ObjectReference")
        ) == .returned(.none))

        let tagged = try Fixture.make(
            links: [(keyword: Fixture.keywordID, ref: Fixture.doorID)]
        )
        // A tagged link never answers the untagged lookup.
        #expect(tagged.call(
            "GetLinkedRef", returnType: .object("ObjectReference")
        ) == .returned(.none))
        #expect(tagged.call(
            "GetLinkedRef",
            arguments: [.object(tagged.handle(Fixture.otherKeywordID))],
            returnType: .object("ObjectReference")
        ) == .returned(.none))
        // Explicit None is the Papyrus default argument, not a type error.
        #expect(tagged.call(
            "GetLinkedRef",
            arguments: [.none],
            returnType: .object("ObjectReference")
        ) == .returned(.none))
    }

    @Test func getLinkedRefRejectsANonObjectKeyword() throws {
        let fixture = try Fixture.make(links: [(keyword: nil, ref: Fixture.doorID)])
        #expect(PapyrusWorldFixture.isInvalidArguments(fixture.call(
            "GetLinkedRef",
            arguments: [.string("LinkCarryStart")],
            returnType: .object("ObjectReference")
        )))
    }

    @Test func activateRecordsActivationAndQueuesOnActivate() throws {
        let fixture = try Fixture.make(events: [(
            "OnActivate", PapyrusWorldFixture.probeBody(note: "lever.onactivate")
        )])
        #expect(fixture.call("Activate", returnType: .boolean) == .returned(.boolean(true)))

        let activation = try #require(fixture.session.worldState.component(
            ReferenceActivationState.self, for: fixture.key
        ))
        #expect(activation.activationCount == 1)
        #expect(activation.lastActivator == .player)
        // A script-side Activate records the activation without claiming the
        // target opened; only the player's use key sets that.
        #expect(!activation.isOpen)

        PapyrusWorldFixture.drain(fixture.session.world)
        #expect(fixture.session.dispatch.notes == ["lever.onactivate"])
    }

    @Test func activateTakesItsActivatorFromArgumentZero() throws {
        let fixture = try Fixture.make()
        #expect(fixture.call(
            "Activate",
            arguments: [.object(fixture.handle(Fixture.doorID))],
            returnType: .boolean
        ) == .returned(.boolean(true)))
        #expect(fixture.session.worldState.component(
            ReferenceActivationState.self, for: fixture.key
        )?.lastActivator == Fixture.key(Fixture.doorID))

        // None falls back to the player, and the ignored
        // abDefaultProcessingOnly flag does not disturb that.
        #expect(fixture.call(
            "Activate", arguments: [.none, .boolean(true)], returnType: .boolean
        ) == .returned(.boolean(true)))
        #expect(fixture.session.worldState.component(
            ReferenceActivationState.self, for: fixture.key
        )?.lastActivator == .player)
    }

    @Test func activateRejectsANonObjectActivator() throws {
        let fixture = try Fixture.make()
        #expect(PapyrusWorldFixture.isInvalidArguments(fixture.call(
            "Activate", arguments: [.string("player")], returnType: .boolean
        )))
        #expect(fixture.session.worldState.component(
            ReferenceActivationState.self, for: fixture.key
        ) == nil)
    }

    /// With no world behind the context every one of these fails with a
    /// reason. The interpreter turns that into the call's declared default, so
    /// a headless script still runs to completion.
    @Test func headlessCallsFailInsteadOfGuessing() {
        let registry = PapyrusNativeRegistry.standard
        let receiver = PapyrusObjectHandle(7)
        for functionName in [
            "Enable", "Disable", "IsEnabled", "Delete",
            "GetPositionX", "GetPositionY", "GetPositionZ", "SetPosition",
            "Activate", "GetLinkedRef"
        ] {
            let result = registry.invoke(PapyrusWorldFixture.methodCall(
                "ObjectReference",
                functionName,
                receiver: receiver,
                arguments: [.float(1)]
            ))
            #expect(
                PapyrusWorldFixture.isInvalidArguments(result),
                "\(functionName) should fail headlessly, got \(result)"
            )
        }
    }
}
