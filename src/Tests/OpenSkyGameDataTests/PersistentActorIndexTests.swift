// The Unique Actor fallback: a base with one persistent placed actor maps to it.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct PersistentActorIndexTests {
    private static let cell: UInt32 = 0x100

    private static func actor(_ formID: UInt32, base: UInt32, flags: UInt32 = 0) -> Data {
        var name = Data()
        name.appendUInt32(base)
        let data = ESMFixture.f32([0, 0, 0, 0, 0, 0])
        return ESMFixture.record(
            "ACHR", formID: formID, flags: flags,
            data: ESMFixture.field("NAME", name) + ESMFixture.field("DATA", data)
        )
    }

    private static func reference(_ formID: UInt32, base: UInt32) -> Data {
        var name = Data()
        name.appendUInt32(base)
        let data = ESMFixture.f32([0, 0, 0, 0, 0, 0])
        return ESMFixture.record(
            "REFR", formID: formID,
            data: ESMFixture.field("NAME", name) + ESMFixture.field("DATA", data)
        )
    }

    private static func plugin() throws -> ESMFile {
        let persistent = ESMFixture.childGroup(
            parent: cell, groupType: 8,
            contents: actor(0x200, base: 0x50) + actor(0x201, base: 0x60) + actor(0x202, base: 0x60)
                + actor(0x205, base: 0x90) + actor(0x206, base: 0x90, flags: 0x800)
                + reference(0x204, base: 0x80)
        )
        let temporary = ESMFixture.childGroup(
            parent: cell, groupType: 9, contents: actor(0x203, base: 0x70)
        )
        let children = ESMFixture.childGroup(
            parent: cell, groupType: 6, contents: persistent + temporary
        )
        let cellRecord = ESMFixture.record("CELL", formID: cell, data: Data())
        return try ESMFile(
            data: ESMFixture.tes4() + ESMFixture.topGroup("CELL", contents: cellRecord + children)
        )
    }

    @Test func aBaseWithOnePersistentActorMapsToIt() throws {
        let plugins = try [(name: "Test.esm", file: Self.plugin())]
        let index = RecordIndex(plugins: plugins, recordTypes: RecordIndex.referenceRecordTypes)
        let placements = PersistentActorIndex.placements(plugins: plugins, index: index)
        let found = PersistentActorIndex.singleReferences(in: placements)
        func key(_ id: UInt32) throws -> ReferenceKey {
            try ReferenceKey(resolved: #require(index.resolvedID(
                FormID(id),
                fromPlugin: "Test.esm"
            )))
        }
        // 0x60 has two enabled copies; 0x90 has one enabled and one that starts disabled.
        #expect(try found == [key(0x50): key(0x200), key(0x90): key(0x205)])
        #expect(try LocationStore(plugins: plugins).uniqueActorReferences[key(0x50)] == key(0x200))
    }

    @Test func placementsHoldEveryPersistentReferenceAndNoTemporaryOne() throws {
        let plugins = try [(name: "Test.esm", file: Self.plugin())]
        let index = RecordIndex(plugins: plugins, recordTypes: RecordIndex.referenceRecordTypes)
        let placements = PersistentActorIndex.placements(plugins: plugins, index: index)
        #expect(placements.map(\.formID.rawValue) == [0x200, 0x201, 0x202, 0x204, 0x205, 0x206])
        #expect(placements.first { $0.formID.rawValue == 0x204 }?.actorBase == nil)
    }
}
