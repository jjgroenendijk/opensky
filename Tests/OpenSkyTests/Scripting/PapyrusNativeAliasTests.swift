// The alias natives over a synthetic quest: `ForceRefTo` and `Clear` move the alias
// and its script, `GetRef` reads an alias slot, and the location alias natives.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyQuestsInterface
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeAliasTests {
    private static let otherObjectID: UInt32 = 0x0000_0702
    private static let locationObjectID: UInt32 = 0x0000_0703

    private var otherKey: ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: Self.otherObjectID)
    }

    private func session() throws -> PapyrusWorldFixture.Session {
        let quest = try PapyrusQuestFixture.quest(
            aliases: PapyrusQuestFixture.forcedAlias(),
            aliasScripts: [PapyrusQuestFixture.aliasScriptSection()]
        )
        let entries = try [PapyrusQuestFixture.aliasReferenceObjectID, Self.otherObjectID]
            .map { objectID in
                try PapyrusWorldFixture.referenceEntry(
                    objectID: objectID, scripts: [], isPersistent: true
                )
            }
        return PapyrusQuestFixture.session(
            quest: quest,
            objects: PapyrusQuestFixture.objects([PapyrusQuestFixture.aliasScriptObject()]),
            entries: entries
        )
    }

    private func slotHandle(_ session: PapyrusWorldFixture.Session) -> PapyrusObjectHandle {
        session.world.aliasSlotHandle(PapyrusAliasSlot(
            quest: PapyrusQuestFixture.questKey, aliasID: PapyrusQuestFixture.aliasID
        ))
    }

    private func call(
        _ session: PapyrusWorldFixture.Session,
        _ script: String, _ name: String,
        on receiver: PapyrusObjectHandle,
        _ arguments: [PapyrusValue] = [],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        PapyrusWorldFixture.registry(for: session).invoke(PapyrusWorldFixture.methodCall(
            script, name, receiver: receiver, arguments: arguments, returnType: returnType
        ))
    }

    private func fill(_ session: PapyrusWorldFixture.Session) throws -> ReferenceKey? {
        let runtime = try #require(session.bridge.questRuntime)
        return try runtime.aliasState(of: PapyrusQuestFixture.questFormID)
            .reference(forAlias: PapyrusQuestFixture.aliasID)
    }

    @Test func forceRefToMovesTheAliasAndItsScript() throws {
        let session = try session()
        let other = session.world.objectHandle(for: otherKey)
        #expect(call(session, "ReferenceAlias", "ForceRefTo", on: slotHandle(session), [
            .object(other)
        ]) == .returned(.none))

        #expect(try fill(session) == otherKey)
        let oldScript = PapyrusQuestFixture.aliasInstanceKey(PapyrusQuestFixture.aliasScript)
        let newScript = PapyrusInstanceKey(
            reference: otherKey, scriptName: PapyrusQuestFixture.aliasScript
        )
        #expect(session.world.instancesByKey[oldScript] == nil)
        #expect(session.world.instancesByKey[newScript] != nil)
        #expect(session.world.questAliasInstanceKeys[PapyrusQuestFixture.questKey]
            == [newScript])
    }

    @Test func getRefOnASlotReadsTheFillAndClearEmptiesIt() throws {
        let session = try session()
        let slot = slotHandle(session)
        let filled = session.world.objectHandle(for: PapyrusQuestFixture.aliasReferenceKey)
        #expect(call(session, "ReferenceAlias", "GetReference", on: slot, returnType: .object(
            "ObjectReference"
        )) == .returned(.object(filled)))

        #expect(call(session, "ReferenceAlias", "Clear", on: slot) == .returned(.none))
        #expect(try fill(session) == nil)
        #expect(session.world.questAliasInstanceCount == 0)
        #expect(call(session, "ReferenceAlias", "GetReference", on: slot, returnType: .object(
            "ObjectReference"
        )) == .returned(.none))
        #expect(call(session, "Alias", "GetOwningQuest", on: slot, returnType: .object("Quest"))
            == .returned(.object(session.world.objectHandle(for: PapyrusQuestFixture.questKey))))
    }

    /// `Self` inside the alias script names the alias too, so the script can clear it.
    @Test func anAliasScriptCanClearItsOwnAlias() throws {
        let session = try session()
        let aliasKey = PapyrusQuestFixture.aliasInstanceKey(PapyrusQuestFixture.aliasScript)
        let handle = try #require(session.world.instancesByKey[aliasKey])
        #expect(call(session, "ReferenceAlias", "Clear", on: handle) == .returned(.none))
        #expect(try fill(session) == nil)
    }

    @Test func locationAliasNativesForceReadAndClear() throws {
        let session = try session()
        let slot = slotHandle(session)
        let location = session.world.objectHandle(
            for: .plugin(name: PapyrusWorldFixture.pluginName, objectID: Self.locationObjectID)
        )
        #expect(call(session, "LocationAlias", "ForceLocationTo", on: slot, [.object(location)])
            == .returned(.none))
        #expect(call(session, "LocationAlias", "GetLocation", on: slot, returnType: .object(
            "Location"
        )) == .returned(.object(location)))
        #expect(call(session, "LocationAlias", "Clear", on: slot) == .returned(.none))
        #expect(call(session, "LocationAlias", "GetLocation", on: slot, returnType: .object(
            "Location"
        )) == .returned(.none))
    }

    @Test func anUnknownAliasIsRefused() throws {
        let session = try session()
        let missing = session.world.aliasSlotHandle(
            PapyrusAliasSlot(quest: PapyrusQuestFixture.questKey, aliasID: 42)
        )
        #expect(PapyrusWorldFixture.isInvalidArguments(
            call(session, "ReferenceAlias", "Clear", on: missing)
        ))
    }
}
