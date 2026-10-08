// The Unique Actor fallback: a base with one persistent placed actor maps to it.

@testable import FormatsTesting
import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct PersistentActorIndexTests {
    private static let cell: UInt32 = 0x100

    private static func actor(_ formID: UInt32, base: UInt32) -> Data {
        var name = Data()
        name.appendUInt32(base)
        let data = ESMFixture.f32([0, 0, 0, 0, 0, 0])
        return ESMFixture.record(
            "ACHR", formID: formID,
            data: ESMFixture.field("NAME", name) + ESMFixture.field("DATA", data)
        )
    }

    private static func plugin() throws -> ESMFile {
        let persistent = ESMFixture.childGroup(
            parent: cell, groupType: 8,
            contents: actor(0x200, base: 0x50) + actor(0x201, base: 0x60) + actor(0x202, base: 0x60)
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
        let found = PersistentActorIndex.singleReferences(plugins: plugins, index: index)
        func key(_ id: UInt32) throws -> ReferenceKey {
            try ReferenceKey(resolved: #require(index.resolvedID(
                FormID(id),
                fromPlugin: "Test.esm"
            )))
        }
        #expect(try found == [key(0x50): key(0x200)])
        #expect(try LocationStore(plugins: plugins).uniqueActorReferences[key(0x50)] == key(0x200))
    }
}
