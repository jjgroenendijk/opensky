// One synthetic save holding every kind of data the import maps, plus one of each kind
// it cannot, and the fake load order that names its forms.

import FormatsTesting
import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsESS

enum ESSImportSaveFixture {
    typealias Ref = ESSChangeFlag.Reference
    typealias Base = ESSChangeFlag.ActorBase

    static let quest: UInt32 = 0x3372B
    static let sword: UInt32 = 0x12EB7
    static let movedReference: UInt32 = 0x1000
    static let aliasReference: UInt32 = 0x1001

    static var records: FakeESSImportRecords {
        var records = FakeESSImportRecords()
        records.add("Skyrim.esm", 0x3C, "WRLD", editorID: "Tamriel")
        records.add("Skyrim.esm", 0x39, "GLOB", editorID: "GameDaysPassed", globalType: .float)
        records.add("Skyrim.esm", 0x1C0F2, "GLOB", editorID: "DragonsAbsorbed", globalType: .short)
        records.add("Skyrim.esm", quest, "QUST", editorID: "MQ101")
        records.add("Skyrim.esm", 0x13746, "RACE", editorID: "NordRace")
        records.add("Skyrim.esm", 0x12FCD, "SPEL")
        records.add("Skyrim.esm", 0x13794, "FACT")
        records.add("Skyrim.esm", 0x2000, "INFO")
        records.add("Skyrim.esm", 0x5000, "CELL", editorID: "HelgenKeep01")
        records.scripts["mq101script"] = [
            "::count_var": "mq101script", "::name_var": "mq101script", "::target_var": "mq101script"
        ]
        return records
    }

    static func save() -> Data {
        var fixture = ESSFixture()
        fixture.plugins = ["Skyrim.esm", "Update.esm", "Missing.esp"]
        fixture.formIDArray = [0x0200_1234]
        fixture.globalData1 = [
            (type: 1, data: playerLocation()), (type: 3, data: globals()),
            (type: 4, data: createdPotion())
        ]
        fixture.globalData3 = [(type: 1001, data: papyrus())]
        fixture.changeForms = [
            playerBase(), playerReference(), movedChange(), unmappedReference(),
            aliasChange(), createdReference(), questChange(),
            ESSFixtureChangeForm(
                kind: 1, value: 0x2000, flags: ESSChangeFlag.Topic.saidOnce, typeIndex: 7,
                data: Data()
            )
        ]
        return fixture.build()
    }

    private static func playerLocation() -> Data {
        ESSBytes.build { writer in
            writer.writeUInt32(0x20)
            ESSBytes.refID(kind: 1, value: 0x3C, into: &writer)
            writer.writeUInt32(UInt32(bitPattern: -3))
            writer.writeUInt32(7)
            ESSBytes.refID(kind: 1, value: 0x3C, into: &writer)
            ESSBytes.vector3(SIMD3(-12000, 30000, 512), into: &writer)
        }
    }

    private static func globals() -> Data {
        ESSBytes.build { writer in
            ESSBytes.vsval(3, into: &writer)
            ESSBytes.refID(kind: 1, value: 0x39, into: &writer)
            writer.writeFloat32(3.25)
            ESSBytes.refID(kind: 1, value: 0x1C0F2, into: &writer)
            writer.writeFloat32(2)
            ESSBytes.refID(kind: 0, value: 1, into: &writer)
            writer.writeFloat32(9)
        }
    }

    private static func createdPotion() -> Data {
        ESSBytes.build { writer in
            ESSBytes.vsval(0, into: &writer)
            ESSBytes.vsval(0, into: &writer)
            ESSBytes.vsval(1, into: &writer)
            ESSBytes.refID(kind: 2, value: 0x40, into: &writer)
            writer.writeUInt32(1)
            ESSBytes.vsval(0, into: &writer)
            ESSBytes.vsval(0, into: &writer)
        }
    }

    private static func papyrus() -> Data {
        var fixture = ESSPapyrusFixture()
        fixture.scripts = [ESSPapyrusFixtureScript(
            name: "MQ101Script", parent: "Quest",
            members: [("::Count_var", "Int"), ("::Name_var", "String"), ("::Target_var", "Actor")]
        )]
        fixture.instances = [
            ESSPapyrusFixtureInstance(
                id: 1, script: "MQ101Script", form: (kind: 1, value: quest),
                variables: [.integer(4), .string("Hadvar"), .object(type: "Actor", id: 2)]
            ),
            ESSPapyrusFixtureInstance(
                id: 2, script: "MQ101Script", form: (kind: 0, value: 1),
                variables: [.integer(1), .null, .null]
            )
        ]
        fixture.activeStacks = [(id: 5, script: "MQ101Script")]
        return fixture.build()
    }

    private static func playerBase() -> ESSFixtureChangeForm {
        let data = ESSBytes.build { writer in
            ESSBytes.vsval(1, into: &writer)
            ESSBytes.refID(kind: 1, value: 0x13794, into: &writer)
            writer.writeUInt8(0)
            for count: UInt32 in [1, 0, 0] {
                ESSBytes.vsval(count, into: &writer)
                if count == 1 {
                    ESSBytes.refID(kind: 1, value: 0x12FCD, into: &writer)
                }
            }
            ESSBytes.refID(kind: 1, value: 0x13746, into: &writer)
            ESSBytes.refID(kind: 1, value: 0x13746, into: &writer)
            writer.writeUInt8(1)
        }
        return ESSFixtureChangeForm(
            kind: 1, value: 0x7, flags: Base.factions | Base.spellList | Base.race | Base.gender,
            typeIndex: 9, data: data
        )
    }

    private static func playerReference() -> ESSFixtureChangeForm {
        let data = ESSBytes.build { writer in
            ESSBytes.refID(kind: 1, value: 0x3C, into: &writer)
            ESSBytes.vector3(SIMD3(-12000, 30000, 512), into: &writer)
            ESSBytes.vector3(SIMD3(0, 0, 1.5), into: &writer)
            writer.write(Data(count: 8))
            ESSBytes.vsval(2, into: &writer)
            ESSBytes.refID(kind: 1, value: 0xF, into: &writer)
            writer.writeUInt32(250)
            ESSBytes.vsval(0, into: &writer)
            ESSBytes.refID(kind: 1, value: sword, into: &writer)
            writer.writeUInt32(1)
            ESSBytes.vsval(1, into: &writer)
            ESSBytes.vsval(1, into: &writer)
            writer.writeUInt8(22)
        }
        return ESSFixtureChangeForm(
            kind: 1, value: 0x14, flags: Ref.move | Ref.inventory, typeIndex: 1, data: data,
            compressed: true
        )
    }

    private static func movedChange() -> ESSFixtureChangeForm {
        let data = ESSBytes.build { writer in
            ESSBytes.refID(kind: 1, value: 0x3C, into: &writer)
            ESSBytes.vector3(SIMD3(10, 20, 30), into: &writer)
            ESSBytes.vector3(.zero, into: &writer)
            writer.writeUInt32(0x800)
            writer.writeUInt16(0)
            writer.writeFloat32(2)
        }
        return ESSFixtureChangeForm(
            kind: 1, value: movedReference, flags: ESSChangeFlag.formFlags | Ref.move | Ref.scale,
            typeIndex: 0, data: data
        )
    }

    private static func unmappedReference() -> ESSFixtureChangeForm {
        ESSFixtureChangeForm(
            kind: 0, value: 1, flags: ESSChangeFlag.formFlags, typeIndex: 0,
            data: Data([0, 8, 0, 0, 0, 0])
        )
    }

    private static func aliasChange() -> ESSFixtureChangeForm {
        let data = ESSBytes.build { writer in
            ESSBytes.vsval(1, into: &writer)
            writer.writeUInt8(136)
            ESSBytes.vsval(1, into: &writer)
            ESSBytes.refID(kind: 1, value: quest, into: &writer)
            writer.writeUInt32(3)
        }
        return ESSFixtureChangeForm(
            kind: 1, value: aliasReference, flags: Ref.extraGameOnly, typeIndex: 0, data: data
        )
    }

    private static func createdReference() -> ESSFixtureChangeForm {
        let data = ESSBytes.build { writer in
            ESSBytes.refID(kind: 1, value: 0x5000, into: &writer)
            ESSBytes.vector3(SIMD3(1, 2, 3), into: &writer)
            ESSBytes.vector3(.zero, into: &writer)
            writer.writeUInt8(0)
            ESSBytes.refID(kind: 1, value: sword, into: &writer)
        }
        return ESSFixtureChangeForm(kind: 2, value: 0x10, flags: Ref.move, typeIndex: 0, data: data)
    }

    private static func questChange() -> ESSFixtureChangeForm {
        let data = ESSBytes.build { writer in
            writer.writeUInt16(0x1)
            ESSBytes.vsval(3, into: &writer)
            for (stage, done) in [(10, 1), (20, 1), (30, 0)] {
                writer.writeUInt16(UInt16(stage))
                writer.writeUInt8(UInt8(done))
            }
        }
        return ESSFixtureChangeForm(
            kind: 1, value: quest,
            flags: ESSChangeFlag.Quest.flags | ESSChangeFlag.Quest.stages, typeIndex: 8, data: data
        )
    }
}
