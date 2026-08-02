import Foundation
@testable import opensky
import Testing

@Suite("VMAD script data")
struct ScriptDataTests {
    @Test("decodes every scalar and array property type")
    func decodesPropertyMatrix() throws {
        let direct = VMADFixture.object(0x0012_3456, unused: 7)
        let script = VMADFixture.Script("MatrixScript", properties: [
            .init("NoneValue", .none),
            .init("ObjectValue", .object(direct)),
            .init("StringValue", .string("Whiterun")),
            .init("IntValue", .integer(-42)),
            .init("FloatValue", .float(3.5)),
            .init("BoolValue", .boolean(true)),
            .init("ObjectValues", .objects([direct, VMADFixture.object(0)])),
            .init("StringValues", .strings(["one", "two"])),
            .init("IntValues", .integers([-1, 2])),
            .init("FloatValues", .floats([1.25, -4])),
            .init("BoolValues", .booleans([true, false]))
        ])

        let data = try decode(VMADFixture.payload(scripts: [script]))
        let properties = try #require(data.scripts.first?.properties)
        #expect(properties.count == 11)
        #expect(properties.map(\.type) == [0, 1, 2, 3, 4, 5, 11, 12, 13, 14, 15])
        #expect(properties[0].value == .none)
        #expect(properties[1].value == .object(direct))
        #expect(properties[2].value == .string("Whiterun"))
        #expect(properties[3].value == .integer(-42))
        #expect(properties[4].value == .float(3.5))
        #expect(properties[5].value == .boolean(true))
        #expect(properties[6].value == .objects([direct, VMADFixture.object(0)]))
        #expect(properties[7].value == .strings(["one", "two"]))
        #expect(properties[8].value == .integers([-1, 2]))
        #expect(properties[9].value == .floats([1.25, -4]))
        #expect(properties[10].value == .booleans([true, false]))
    }

    @Test("decodes both object word orders")
    func decodesBothObjectFormats() throws {
        let object = VMADFixture.object(0x0102_0304, alias: 19, unused: 0xABCD)
        for format in [ScriptObjectFormat.formIDFirst, .formIDLast] {
            let payload = VMADFixture.payload(
                objectFormat: format,
                scripts: [.init("ObjectScript", properties: [
                    .init("Target", .object(object))
                ])]
            )
            let data = try decode(payload)
            #expect(data.objectFormat == format)
            #expect(data.scripts.first?.properties.first?.value == .object(object))
            #expect(data.skipped.ranked.first?.name == "alias object")
        }
    }

    @Test("versions before four omit status bytes")
    func decodesLegacyStatusLayout() throws {
        let payload = VMADFixture.payload(
            version: 3,
            objectFormat: .formIDFirst,
            scripts: [.init("LegacyScript", flags: 3, properties: [
                .init("Value", .integer(9), flags: 3)
            ])]
        )
        let data = try decode(payload)
        #expect(data.version == 3)
        #expect(data.scripts.first?.flags.isEmpty == true)
        #expect(data.scripts.first?.properties.first?.flags == .edited)
    }

    /// QUST tails are decoded instead (QuestFragmentTests); the other four
    /// carriers still record one reason-tagged skip and consume the remainder.
    @Test("fragment carriers skip and rank their bounded tail")
    func skipsFragmentTail() throws {
        var data = ScriptData(ownerType: "SCEN")
        let payload = VMADFixture.payload(scripts: [], tail: Data([2, 0, 0, 0]))
        #expect(try data.decode(field: ESMField(type: "VMAD", data: payload)))
        #expect(data.skipped.ranked.first?.name == "SCEN fragments")
        #expect(data.skipped.total == 1)
    }

    @Test("rejects malformed payloads with ScriptDataError")
    func rejectsMalformedPayloads() {
        let tooOld = malformedHeader(version: 1)
        #expect(throws: ScriptDataError.unsupportedVersion(1)) {
            _ = try decode(tooOld)
        }

        let tooNew = malformedHeader(version: 6)
        #expect(throws: ScriptDataError.unsupportedVersion(6)) {
            _ = try decode(tooNew)
        }

        let badFormat = malformedHeader(version: 5, objectFormat: 3)
        #expect(throws: ScriptDataError.unsupportedObjectFormat(3)) {
            _ = try decode(badFormat)
        }

        let truncated = VMADFixture.payload(scripts: [
            .init("Broken", properties: [.init("Value", .integer(1))])
        ]).dropLast()
        #expect(throws: ScriptDataError.self) {
            _ = try decode(Data(truncated))
        }

        var impossible = Data()
        impossible.appendUInt16(5)
        impossible.appendUInt16(2)
        impossible.appendUInt16(.max)
        #expect(throws: ScriptDataError.self) {
            _ = try decode(impossible)
        }

        var earlyArray = Data()
        earlyArray.appendUInt16(4)
        earlyArray.appendUInt16(2)
        earlyArray.appendUInt16(1)
        earlyArray.appendTestVMADString("Broken")
        earlyArray.append(0)
        earlyArray.appendUInt16(1)
        earlyArray.appendTestVMADString("Values")
        earlyArray.append(15)
        earlyArray.append(1)
        earlyArray.appendUInt32(0)
        #expect(throws: ScriptDataError.arrayRequiresVersionFive(type: 15, version: 4)) {
            _ = try decode(earlyArray)
        }

        var unknownType = Data()
        unknownType.appendUInt16(5)
        unknownType.appendUInt16(2)
        unknownType.appendUInt16(1)
        unknownType.appendTestVMADString("Broken")
        unknownType.append(0)
        unknownType.appendUInt16(1)
        unknownType.appendTestVMADString("Value")
        unknownType.append(99)
        unknownType.append(1)
        #expect(throws: ScriptDataError.unknownPropertyType(99)) {
            _ = try decode(unknownType)
        }
    }

    @Test("accepts an XXXX-extended VMAD over 64 KB")
    func decodesExtendedVMADField() throws {
        let large = String(repeating: "x", count: 65530)
        let payload = VMADFixture.payload(scripts: [
            .init("LargeScript", properties: [.init("Text", .string(large))])
        ])
        #expect(payload.count > Int(UInt16.max))

        var name = Data()
        name.appendUInt32(1)
        let fields = ESMFixture.field("NAME", name)
            + ESMFixture.field("DATA", Data(count: 24))
            + ESMFixture.longField("VMAD", payload)
        let reference = try PlacedReference(
            record: parse(ESMFixture.record("REFR", formID: 2, data: fields))
        )
        #expect(reference.scriptData.scripts.first?.properties.first?.value == .string(large))
    }

    @Test("record decoders forward VMAD")
    func recordDecodersForwardVMAD() throws {
        let vmad = ESMFixture.field("VMAD", VMADFixture.payload(scripts: [
            .init("Forwarded", properties: [])
        ]))

        var name = Data()
        name.appendUInt32(1)
        let reference = try PlacedReference(record: parse(ESMFixture.record(
            "REFR",
            data: nameField(name) + ESMFixture.field("DATA", Data(count: 24)) + vmad
        )))
        #expect(reference.scriptData.scripts.first?.name == "Forwarded")

        let actor = try PlacedActor(record: parse(ESMFixture.record(
            "ACHR",
            data: nameField(name) + ESMFixture.field("DATA", Data(count: 24)) + vmad
        )))
        #expect(actor.scriptData.scripts.first?.name == "Forwarded")

        let base = try ModelBase(record: parse(ESMFixture.record("ACTI", data: vmad)))
        #expect(base.scriptData.scripts.first?.name == "Forwarded")

        let actorBase = try ActorBase(
            record: parse(ESMFixture.record(
                "NPC_",
                data: ESMFixture.field("ACBS", Data(count: 24)) + vmad
            )),
            localized: false
        )
        #expect(actorBase.scriptData.scripts.first?.name == "Forwarded")
    }

    private func decode(_ payload: Data) throws -> ScriptData {
        var data = ScriptData()
        _ = try data.decode(field: ESMField(type: "VMAD", data: payload))
        return data
    }

    private func parse(_ bytes: Data) throws -> ESMRecord {
        try GlobalFixture.parse(bytes)
    }

    private func nameField(_ data: Data) -> Data {
        ESMFixture.field("NAME", data)
    }

    private func malformedHeader(
        version: Int16,
        objectFormat: Int16 = 2
    ) -> Data {
        var data = Data()
        data.appendUInt16(UInt16(bitPattern: version))
        data.appendUInt16(UInt16(bitPattern: objectFormat))
        data.appendUInt16(0)
        return data
    }
}

extension Data {
    fileprivate mutating func appendTestVMADString(_ value: String) {
        let bytes = Data(value.utf8)
        appendUInt16(UInt16(bytes.count))
        append(bytes)
    }
}
