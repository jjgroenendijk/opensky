// Interaction text and suppression fields on synthetic model-base records.

import Foundation
@testable import opensky
import Testing

extension RecordDecoderTests {
    @Test func decodesModelBaseForEachSupportedType() throws {
        for type in ["MSTT", "TREE", "FURN", "ACTI", "CONT", "DOOR"] {
            let fields = ESMFixture.field("EDID", ESMFixture.zstring("Some\(type)"))
                + ESMFixture.field("FULL", ESMFixture.zstring("\(type) Name"))
                + ESMFixture.field("MODL", ESMFixture.zstring("Meshes\\\(type)\\thing.nif"))
            let base = try ModelBase(
                record: record(ESMFixture.record(type, formID: 0x77, data: fields))
            )
            #expect(base.formID == FormID(0x77))
            #expect(base.recordType == FourCC(stringLiteral: type))
            #expect(base.editorID == "Some\(type)")
            #expect(base.name == .inline("\(type) Name"))
            #expect(base.modelPath == "Meshes\\\(type)\\thing.nif")
        }
    }

    @Test func modelBaseWithoutModelIsMarker() throws {
        let base = try ModelBase(
            record: record(ESMFixture.record("TREE", data: Data()))
        )
        #expect(base.modelPath == nil)
    }

    @Test func modelBaseRejectsUnsupportedRecordType() throws {
        let statBytes = ESMFixture.record("STAT", data: Data())
        #expect(throws: (any Error).self) {
            _ = try ModelBase(record: record(statBytes))
        }
    }

    @Test func decodesLocalizedNameAndActivatorOverride() throws {
        var name = Data()
        name.appendUInt32(0x1234)
        var override = Data()
        override.appendUInt32(0x5678)
        let fields = ESMFixture.field("FULL", name)
            + ESMFixture.field("RNAM", override)
        let base = try ModelBase(
            record: record(ESMFixture.record("ACTI", data: fields)),
            localized: true
        )
        #expect(base.name == .tableID(0x1234))
        #expect(base.activateTextOverride == .tableID(0x5678))
    }

    @Test func ignoresActivatorOverrideOnOtherRecordTypes() throws {
        let fields = ESMFixture.field("RNAM", ESMFixture.zstring("Mine"))
        let base = try ModelBase(
            record: record(ESMFixture.record("DOOR", data: fields))
        )
        #expect(base.activateTextOverride == nil)
    }

    @Test func rejectsTruncatedLocalizedModelBaseText() throws {
        let fields = ESMFixture.field("FULL", Data([1, 2, 3]))
        #expect(throws: (any Error).self) {
            _ = try ModelBase(
                record: record(ESMFixture.record("ACTI", data: fields)),
                localized: true
            )
        }
    }

    @Test func recordFlagsSuppressManualInteraction() throws {
        let ignoredActivator = try ModelBase(record: record(ESMFixture.record(
            "ACTI", flags: 1 << 20, data: Data()
        )))
        var doorFlags = Data()
        doorFlags.append(0x02)
        let automaticDoor = try ModelBase(record: record(ESMFixture.record(
            "DOOR", data: ESMFixture.field("FNAM", doorFlags)
        )))
        var furnitureMarkers = Data()
        furnitureMarkers.appendUInt32(0x0200_0000)
        let disabledFurniture = try ModelBase(record: record(ESMFixture.record(
            "FURN", data: ESMFixture.field("MNAM", furnitureMarkers)
        )))

        #expect(!ignoredActivator.allowsManualInteraction)
        #expect(!automaticDoor.allowsManualInteraction)
        #expect(!disabledFurniture.allowsManualInteraction)
    }
}
