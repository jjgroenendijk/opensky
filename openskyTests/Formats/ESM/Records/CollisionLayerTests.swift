// Synthetic COLL decode and resolved-link tests. Layout: UESP COLL and xEdit
// dev-4.1.6 wbDefinitionsTES5.pas lines 7614-7637.

import Foundation
@testable import opensky
import Testing

struct CollisionLayerTests {
    @Test func decodesFieldsAndRejectsTheWrongType() throws {
        let layer = try CollisionLayer(
            record: record(type: "COLL", fields: fields(editorID: "L_ACTORZONE")),
            localized: false
        )
        #expect(layer.editorID == "L_ACTORZONE")
        #expect(layer.recordDescription == .inline("Actors"))
        #expect(layer.index == 7)
        #expect(layer.flags.contains(.sensor))
        #expect(layer.debugColor == ReferenceRecordColor(
            red: 10, green: 20, blue: 30, alpha: 255
        ))
        #expect(layer.interactablesCount == 2)
        #expect(layer.collidesWith == [FormID(1), FormID(2)])

        let wrong = try record(type: "KYWD", fields: Data())
        #expect(throws: ESMError.self) {
            try CollisionLayer(record: wrong, localized: false)
        }
    }

    @Test func malformedLinkArrayIsTalliedWithoutThrowing() throws {
        let layer = try CollisionLayer(
            record: record(
                type: "COLL",
                fields: ESMFixture.field("CNAM", Data([1, 2, 3]))
            ),
            localized: false
        )
        #expect(layer.collidesWith.isEmpty)
        #expect(layer.skipped.counts[.malformedField("CNAM")] == 1)
    }

    @Test func storeResolvesCrossPluginLinksAndLaterOverride() throws {
        let base = try plugin(records: [
            ESMFixture.record("COLL", formID: 1, data: fields(editorID: "Actor", links: [2])),
            ESMFixture.record("COLL", formID: 2, data: fields(editorID: "Static", links: []))
        ])
        let patch = try plugin(
            masters: ["Base.esm"],
            records: [ESMFixture.record(
                "COLL", formID: 1, data: fields(editorID: "PatchedActor", links: [2])
            )]
        )
        let store = CollisionLayerStore(plugins: [
            ("Base.esm", base), ("Patch.esp", patch)
        ])
        let actorID = ResolvedFormID(plugin: "Base.esm", objectID: 1)
        let staticID = ResolvedFormID(plugin: "Base.esm", objectID: 2)
        let actor = try #require(store.layer(actorID))
        #expect(actor.layer.editorID == "PatchedActor")
        #expect(actor.sourcePlugin == "Patch.esp")
        #expect(actor.collidesWith == [staticID])
        #expect(store.layer(editorID: "patchedactor")?.id == actorID)
        let projectile = Projectile(
            formID: FormID(10), gravityFactor: 0.35, speed: 3600, range: 60000,
            collisionLayer: FormID(2)
        )
        #expect(store.collisionLayer(for: projectile, fromPlugin: "Patch.esp")?.id == staticID)
    }

    private func fields(editorID: String, links: [UInt32] = [1, 2]) -> Data {
        var scalar = Data()
        scalar.appendUInt32(7)
        var flags = Data()
        flags.appendUInt32(0x02)
        var count = Data()
        count.appendUInt32(UInt32(links.count))
        var cnam = Data()
        links.forEach { cnam.appendUInt32($0) }
        return ESMFixture.field("EDID", ESMFixture.zstring(editorID))
            + ESMFixture.field("DESC", ESMFixture.zstring("Actors"))
            + ESMFixture.field("BNAM", scalar)
            + ESMFixture.field("FNAM", Data([10, 20, 30, 255]))
            + ESMFixture.field("GNAM", flags)
            + ESMFixture.field("MNAM", ESMFixture.zstring(editorID))
            + ESMFixture.field("INTV", count)
            + (links.isEmpty ? Data() : ESMFixture.field("CNAM", cnam))
    }

    private func record(type: String, fields: Data) throws -> ESMRecord {
        let file = try plugin(type: type, records: [
            ESMFixture.record(type, formID: 1, data: fields)
        ])
        let group = try #require(file.topGroups.first)
        let children = try group.children()
        guard case let .record(record) = try #require(children.first) else {
            throw ESMError.malformed("fixture record missing")
        }
        return record
    }

    private func plugin(
        masters: [String] = [],
        type: String = "COLL",
        records: [Data]
    ) throws -> ESMFile {
        try ESMFile(data: ESMFixture.tes4(masters: masters)
            + ESMFixture.topGroup(type, contents: records.reduce(Data(), +)))
    }
}
