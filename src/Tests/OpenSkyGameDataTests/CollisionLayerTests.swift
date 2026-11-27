// Synthetic COLL decode and resolved-link tests. Layout: UESP COLL and xEdit
// dev-4.1.6 wbDefinitionsTES5.pas lines 7614-7637.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct CollisionLayerTests {
    @Test func decodesFieldsAndRejectsTheWrongType() throws {
        let layer = try CollisionLayer(
            record: ESMFixture.parsedRecord(type: "COLL", fields: fields(editorID: "L_ACTORZONE")),
            localized: false
        )
        #expect(layer.formID == FormID(1))
        #expect(layer.editorID == "L_ACTORZONE")
        #expect(layer.name == "L_ACTORZONE")
        #expect(layer.recordDescription == .inline("Actors"))
        #expect(layer.index == 7)
        #expect(layer.flags.contains(.sensor))
        #expect(layer.debugColor == ReferenceRecordColor(
            red: 10, green: 20, blue: 30, alpha: 255
        ))
        #expect(layer.interactablesCount == 2)
        #expect(layer.collidesWith == [FormID(1), FormID(2)])

        let wrong = try ESMFixture.parsedRecord(type: "KYWD", fields: Data())
        #expect(throws: ESMError.self) {
            try CollisionLayer(record: wrong, localized: false)
        }
    }

    /// The GNAM flag bits docs/formats/records.md lists.
    @Test func flagBitsMatchTheDocumentedList() {
        let documented: [(CollisionLayer.Flags, UInt32)] = [
            (.triggerVolume, 0x01), (.sensor, 0x02), (.navmeshObstacle, 0x04)
        ]
        for (flag, bits) in documented {
            #expect(flag.rawValue == bits)
        }
    }

    @Test func malformedLinkArrayIsTalliedWithoutThrowing() throws {
        let layer = try CollisionLayer(
            record: ESMFixture.parsedRecord(
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

    /// `XTRI` layers: flag 0x01 is a trigger, a layer the character layer (index 30)
    /// collides with is solid, and the rest are neither.
    @Test func layerRolesFollowTheTriggerFlagAndTheCharacterLayer() throws {
        func layer(_ formID: UInt32, index: UInt32, flags: UInt32, links: [UInt32] = []) throws
            -> CollisionLayer
        {
            var bnam = Data()
            bnam.appendUInt32(index)
            var gnam = Data()
            gnam.appendUInt32(flags)
            var cnam = Data()
            links.forEach { cnam.appendUInt32($0) }
            let data = ESMFixture.field("BNAM", bnam) + ESMFixture.field("GNAM", gnam)
                + (links.isEmpty ? Data() : ESMFixture.field("CNAM", cnam))
            let record = try ESMFixture.parseRecord(
                ESMFixture.record("COLL", formID: formID, data: data)
            )
            return try CollisionLayer(record: record, localized: false)
        }
        let roles = try CollisionLayerRoles(layers: [
            layer(0x30, index: 30, flags: 0, links: [0x01, 0x16]),
            layer(0x01, index: 1, flags: 0),
            layer(0x16, index: 22, flags: 0x01),
            layer(0x31, index: 49, flags: 0)
        ])
        #expect(roles.role(ofLayer: nil) == .trigger)
        #expect(roles.role(ofLayer: 22) == .trigger)
        #expect(roles.role(ofLayer: 1) == .solid)
        #expect(roles.role(ofLayer: 49) == .neither)
        #expect(CollisionLayerRoles.empty.role(ofLayer: 49) == .trigger)
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

    private func plugin(
        masters: [String] = [],
        type: String = "COLL",
        records: [Data]
    ) throws -> ESMFile {
        try ESMFile(data: ESMFixture.tes4(masters: masters)
            + ESMFixture.topGroup(type, contents: records.reduce(Data(), +)))
    }
}
