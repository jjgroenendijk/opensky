// Change form envelopes and the typed reference, actor base, quest, and topic decoders,
// over bytes built in code.

import FormatsTesting
import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESS
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct ESSChangeFormTests {
    private typealias Ref = ESSChangeFlag.Reference

    private static func file(_ forms: [ESSFixtureChangeForm]) throws -> ESSFile {
        var fixture = ESSFixture()
        fixture.changeForms = forms
        return try ESSFile(data: fixture.build())
    }

    @Test(arguments: [false, true])
    func envelopeReadsStoredAndCompressedData(_ compressed: Bool) throws {
        let payload = Data((0 ..< 300).map { UInt8($0 % 7) })
        let file = try Self.file([ESSFixtureChangeForm(
            kind: 1, value: 0x1234, flags: 0x8000_0001, typeIndex: 8, data: payload,
            compressed: compressed
        )])
        let form = try #require(file.changeForms.first)
        #expect(form.type?.signature == "QUST")
        #expect(form.isCompressed == compressed)
        #expect(try form.data() == payload)
        #expect(form.flags == 0x8000_0001)
    }

    @Test(arguments: [(UInt8(0), 1), (1, 2), (2, 4)])
    func envelopeReadsEachLengthSize(_ bits: UInt8, _ size: Int) throws {
        var writer = BinaryWriter()
        ESSBytes.refID(kind: 1, value: 0x14, into: &writer)
        writer.writeUInt32(0)
        writer.writeUInt8(bits << 6 | 0)
        writer.writeUInt8(74)
        for _ in 0 ..< 2 {
            switch size {
            case 1: writer.writeUInt8(writer.count == 9 ? 3 : 0)
            case 2: writer.writeUInt16(writer.count == 9 ? 3 : 0)
            default: writer.writeUInt32(writer.count == 9 ? 3 : 0)
            }
        }
        writer.write(Data([7, 8, 9]))
        var reader = ESSReader(writer.data)
        let forms = try ESSChangeForm.read(&reader, count: 1)
        #expect(forms.first?.lengthSize == size)
        #expect(forms.first?.storedData == Data([7, 8, 9]))
        #expect(reader.isAtEnd)
    }

    @Test func referenceDecodesMoveFlagsScaleAndLock() throws {
        let data = ESSBytes.build { writer in
            ESSBytes.refID(kind: 1, value: 0x3C, into: &writer)
            ESSBytes.vector3(SIMD3(100, 200, 300), into: &writer)
            ESSBytes.vector3(SIMD3(0, 0, 1.5), into: &writer)
            writer.writeUInt32(0x800)
            writer.writeUInt16(0)
            writer.writeFloat32(2)
            ESSBytes.vsval(1, into: &writer)
            writer.writeUInt8(42)
            writer.writeUInt8(50)
            writer.writeUInt8(0)
            ESSBytes.refID(kind: 1, value: 0x0002_0000, into: &writer)
            writer.write(Data(count: 8))
        }
        let flags = ESSChangeFlag.formFlags | Ref.move | Ref.scale | ESSChangeFlag.Object.extraLock
        let change = try ESSReferenceChange(ESSChangeForm(
            form: ESSRefID(kind: .default, value: 0x1000), flags: flags, typeIndex: 0,
            version: 74, data: ESSChangeFormData(stored: data)
        ))
        #expect(change.status == .complete)
        #expect(change.placement?.position == SIMD3(100, 200, 300))
        #expect(change.isDisabled == true)
        #expect(change.isDeleted == false)
        #expect(change.scale == 2)
        #expect(change.extraData?.entries == [
            .lock(level: 50, key: ESSRefID(kind: .default, value: 0x0002_0000))
        ])
    }

    @Test func referenceDecodesInventoryWithWornItem() throws {
        let data = ESSBytes.build { writer in
            ESSBytes.vsval(2, into: &writer)
            ESSBytes.refID(kind: 1, value: 0xF, into: &writer)
            writer.writeUInt32(250)
            ESSBytes.vsval(0, into: &writer)
            ESSBytes.refID(kind: 1, value: 0x12EB7, into: &writer)
            writer.writeUInt32(1)
            ESSBytes.vsval(1, into: &writer)
            ESSBytes.vsval(2, into: &writer)
            writer.writeUInt8(22)
            writer.writeUInt8(36)
            writer.writeUInt16(1)
        }
        let change = try ESSReferenceChange(ESSChangeForm(
            form: ESSRefID(kind: .default, value: 0x14), flags: Ref.inventory, typeIndex: 1,
            version: 74, data: ESSChangeFormData(stored: Data(count: 8) + data)
        ))
        #expect(change.isActor)
        let items = try #require(change.inventory)
        #expect(items.map(\.count) == [250, 1])
        #expect(items.map(\.isWorn) == [false, true])
        #expect(change.status == .complete)
    }

    @Test func unknownExtraDataBlocksTheRest() throws {
        let data = ESSBytes.build { writer in
            ESSBytes.vsval(2, into: &writer)
            writer.writeUInt8(33)
            ESSBytes.refID(kind: 1, value: 0x5, into: &writer)
            writer.writeUInt8(45)
            writer.write(Data(count: 40))
        }
        let change = try ESSReferenceChange(ESSChangeForm(
            form: ESSRefID(kind: .default, value: 0x1000),
            flags: Ref.extraOwnership | Ref.inventory, typeIndex: 0, version: 74,
            data: ESSChangeFormData(stored: data)
        ))
        #expect(change.status == .partial(blockedBy: "extra data type 45"))
        #expect(change.extraData?.entries == [.ownership(ESSRefID(kind: .default, value: 5))])
        #expect(change.inventory == nil)
    }

    @Test func createdReferenceReadsItsBase() throws {
        let data = ESSBytes.build { writer in
            ESSBytes.refID(kind: 1, value: 0x3C, into: &writer)
            ESSBytes.vector3(SIMD3(1, 2, 3), into: &writer)
            ESSBytes.vector3(.zero, into: &writer)
            writer.writeUInt8(0)
            ESSBytes.refID(kind: 1, value: 0xF, into: &writer)
        }
        let change = try ESSReferenceChange(ESSChangeForm(
            form: ESSRefID(kind: .created, value: 0x10), flags: Ref.move, typeIndex: 0,
            version: 74, data: ESSChangeFormData(stored: data)
        ))
        #expect(change.status == .complete)
        #expect(change.placement?.createdBase == ESSRefID(kind: .default, value: 0xF))
    }

    @Test func actorBaseDecodesIdentityFields() throws {
        typealias Base = ESSChangeFlag.ActorBase
        var acbs = Data(count: 24)
        acbs[8] = 12
        let data = ESSBytes.build { writer in
            writer.write(acbs)
            ESSBytes.vsval(1, into: &writer)
            ESSBytes.refID(kind: 1, value: 0x13794, into: &writer)
            writer.writeUInt8(2)
            for count: UInt32 in [1, 0, 1] {
                ESSBytes.vsval(count, into: &writer)
                if count == 1 {
                    ESSBytes.refID(kind: 1, value: 0x12FCD, into: &writer)
                }
            }
            ESSBytes.wstring("Lydia", into: &writer)
            writer.write(Data((0 ..< 52).map { UInt8($0) }))
            ESSBytes.refID(kind: 1, value: 0x13746, into: &writer)
            ESSBytes.refID(kind: 1, value: 0x13746, into: &writer)
            writer.writeUInt8(0)
            writer.writeUInt8(1)
        }
        let flags = Base.baseData | Base.factions | Base.spellList | Base.fullName | Base.skills
            | Base.race | Base.face | Base.gender
        let change = try ESSActorBaseChange(ESSChangeForm(
            form: ESSActorBaseChange.playerBase, flags: flags, typeIndex: 9, version: 74,
            data: ESSChangeFormData(stored: data)
        ))
        #expect(change.status == .complete)
        #expect(change.level == 12)
        #expect(change.factions?.map(\.rank) == [2])
        #expect(change.spells?.count == 1)
        #expect(change.shouts?.count == 1)
        #expect(change.name == "Lydia")
        #expect(change.skillValues?.count == 18)
        #expect(change.race == ESSRefID(kind: .default, value: 0x13746))
        #expect(change.face == nil)
        #expect(change.isFemale == true)
    }

    @Test func actorBaseAttributesBlockLaterFields() throws {
        typealias Base = ESSChangeFlag.ActorBase
        let change = try ESSActorBaseChange(ESSChangeForm(
            form: ESSActorBaseChange.playerBase, flags: Base.baseData | Base.attributes | Base.race,
            typeIndex: 9, version: 74, data: ESSChangeFormData(stored: Data(count: 40))
        ))
        #expect(change.status == .partial(blockedBy: "ACTOR_BASE_ATTRIBUTES"))
        #expect(change.race == nil)
        #expect(change.level == 0)
    }

    @Test func questDecodesStagesObjectivesAndFlags() throws {
        typealias Quest = ESSChangeFlag.Quest
        let data = ESSBytes.build { writer in
            writer.writeUInt16(0x0001)
            ESSBytes.vsval(2, into: &writer)
            writer.writeUInt16(10)
            writer.writeUInt8(1)
            writer.writeUInt16(20)
            writer.writeUInt8(1)
            ESSBytes.vsval(1, into: &writer)
            writer.writeUInt32(10)
            writer.writeUInt32(1)
            writer.writeUInt8(1)
        }
        let change = try ESSQuestChange(ESSChangeForm(
            form: ESSRefID(kind: .default, value: 0x3372B),
            flags: Quest.flags | Quest.stages | Quest.objectives | Quest.alreadyRun,
            typeIndex: 8, version: 74, data: ESSChangeFormData(stored: data)
        ))
        #expect(change.status == .complete)
        #expect(change.questFlags == 1)
        #expect(change.currentStage == 20)
        #expect(change.objectives?.count == 1)
        #expect(change.alreadyRun == true)
    }

    @Test func questScriptTailIsReportedAsBlocked() throws {
        typealias Quest = ESSChangeFlag.Quest
        let change = try ESSQuestChange(ESSChangeForm(
            form: ESSRefID(kind: .default, value: 0x3372B), flags: Quest.flags | Quest.script,
            typeIndex: 8, version: 74,
            data: ESSChangeFormData(stored: Data([1, 0, 9, 9]))
        ))
        #expect(change.status == .partial(blockedBy: "QUEST_SCRIPT (2 bytes)"))
        #expect(change.questFlags == 1)
    }

    @Test func surveyCountsTypesFlagsAndOutcomes() throws {
        let quest = ESSFixtureChangeForm(
            kind: 1, value: 0x1, flags: ESSChangeFlag.Quest.flags, typeIndex: 8, data: Data([1, 0])
        )
        let info = ESSFixtureChangeForm(
            kind: 1, value: 0x2, flags: ESSChangeFlag.Topic.saidOnce, typeIndex: 7, data: Data()
        )
        let broken = ESSFixtureChangeForm(
            kind: 1, value: 0x3, flags: ESSChangeFlag.Quest.stages, typeIndex: 8, data: Data()
        )
        let cell = ESSFixtureChangeForm(
            kind: 1,
            value: 0x4,
            flags: 2,
            typeIndex: 6,
            data: Data([1])
        )
        let survey = try ESSChangeFormSurvey(Self.file([quest, info, broken, cell]).changeForms)
        #expect(survey.total == 4)
        #expect(survey.row("QUST")?.count == 2)
        #expect(survey.row("QUST")?.complete == 1)
        #expect(survey.row("QUST")?.failed.count == 1)
        #expect(survey.row("INFO")?.complete == 1)
        #expect(survey.row("CELL")?.hasDecoder == false)
        #expect(survey.row("QUST")?.flags[ESSChangeFlag.Quest.flags] == 1)
    }
}
