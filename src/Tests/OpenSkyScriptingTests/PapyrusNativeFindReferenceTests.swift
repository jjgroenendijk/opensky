// The radius searches over a synthetic cell: two levers of one base, an actor at the
// origin, and the player far away.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusNativeFindReferenceTests {
    private static let nearLeverID: UInt32 = 0x0000_0A01
    private static let farLeverID: UInt32 = 0x0000_0A02
    private static let actorID: UInt32 = 0x0000_0A03
    private static let leverBase: UInt32 = 0x100
    private static let listID: UInt32 = 0x0000_0A10

    private static func session() throws -> PapyrusWorldFixture.Session {
        let entries = try [
            PapyrusWorldFixture.referenceEntry(
                objectID: nearLeverID, scripts: [], placement: SIMD3(3, 4, 0)
            ),
            PapyrusWorldFixture.referenceEntry(
                objectID: farLeverID, scripts: [], placement: SIMD3(50, 0, 0)
            ),
            PapyrusWorldFixture.actorEntry(objectID: actorID, base: 0x200, scripts: [])
        ]
        let session = PapyrusWorldFixture.session(objects: [], entries: entries)
        let file = try KeywordFixture.plugin(formLists: [
            FormListFixture.recordBytes(formID: listID, entries: [leverBase])
        ])
        session.bridge.keywordStore = KeywordStore(index: RecordIndex(
            plugins: [("Skyrim.esm", file)], recordTypes: RecordIndex.referenceRecordTypes
        ))
        session.bridge.formListStore = FormListStore(plugins: [("Skyrim.esm", file)])
        session.bridge.perceptionNatives.livePosition = { $0 == .player ? SIMD3(1000, 0, 0) : nil }
        return session
    }

    private static func find(
        _ session: PapyrusWorldFixture.Session, _ name: String, _ form: UInt32?, radius: Float
    ) -> PapyrusNativeResult {
        let point: [PapyrusValue] = [.float(0), .float(0), .float(0), .float(radius)]
        let base = form.map { [PapyrusValue.object(handle(session, $0))] } ?? []
        return PapyrusWorldFixture.registry(for: session).invoke(PapyrusWorldFixture.methodCall(
            "Game", name, receiver: nil, arguments: base + point, returnType: .object("Form")
        ))
    }

    private static func handle(
        _ session: PapyrusWorldFixture.Session,
        _ id: UInt32
    ) -> PapyrusObjectHandle {
        session.world.objectHandle(for: .plugin(name: PapyrusWorldFixture.pluginName, objectID: id))
    }

    @Test func theClosestReferenceOfABaseIsInsideTheRadius() throws {
        let session = try Self.session()
        let near = PapyrusNativeResult.returned(.object(Self.handle(session, Self.nearLeverID)))
        #expect(Self.find(session, "FindClosestReferenceOfType", Self.leverBase, radius: 100)
            == near)
        #expect(Self.find(session, "FindClosestReferenceOfAnyTypeInList", Self.listID, radius: 100)
            == near)
        #expect(Self.find(session, "FindRandomReferenceOfType", Self.leverBase, radius: 10) == near)
        #expect(Self.find(session, "FindClosestReferenceOfType", Self.leverBase, radius: 4)
            == .returned(.none))
    }

    @Test func actorSearchesCountThePlayer() throws {
        let session = try Self.session()
        #expect(Self.find(session, "FindClosestActor", nil, radius: 2000)
            == .returned(.object(Self.handle(session, Self.actorID))))
        session.bridge.write(ReferenceEnableState.disabled.erased, for: .plugin(
            name: PapyrusWorldFixture.pluginName, objectID: Self.actorID
        ))
        #expect(Self.find(session, "FindRandomActor", nil, radius: 2000)
            == .returned(.object(session.world.objectHandle(for: .player))))
        #expect(Self.find(session, "FindRandomActor", nil, radius: 10) == .returned(.none))
    }
}
