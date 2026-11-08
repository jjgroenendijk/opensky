// The `NPC_` change decoder over bytes built in code: identity fields, class, face, and
// the attribute block that stops the read.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESS
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct ESSActorBaseChangeTests {
    private typealias Base = ESSChangeFlag.ActorBase

    @Test func actorBaseDecodesIdentityFields() throws {
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

    @Test func actorBaseDecodesFormFlagsClassAndFace() throws {
        let data = ESSBytes.build { writer in
            writer.writeUInt32(0x40)
            writer.writeUInt16(0)
            ESSBytes.refID(kind: 1, value: 0x13176, into: &writer)
            writer.writeUInt8(1)
            ESSBytes.refID(kind: 1, value: 0xA04, into: &writer)
            writer.write(Data([200, 150, 100, 255]))
            ESSBytes.refID(kind: 1, value: 0xD64, into: &writer)
            ESSBytes.vsval(1, into: &writer)
            ESSBytes.refID(kind: 1, value: 0x51, into: &writer)
            writer.writeUInt8(1)
            writer.writeUInt32(1)
            writer.writeFloat32(0.5)
            writer.writeUInt32(1)
            writer.writeUInt32(3)
        }
        let change = try ESSActorBaseChange(ESSChangeForm(
            form: ESSRefID(kind: .default, value: 0x13BBF),
            flags: ESSChangeFlag.formFlags | Base.npcClass | Base.face, typeIndex: 9,
            version: 74, data: ESSChangeFormData(stored: data)
        ))
        #expect(change.status == .complete)
        #expect(change.form == ESSRefID(kind: .default, value: 0x13BBF))
        #expect(change.formFlags == 0x40)
        #expect(change.npcClass == ESSRefID(kind: .default, value: 0x13176))
        let face = try #require(change.face)
        #expect(face.hairColor == ESSRefID(kind: .default, value: 0xA04))
        #expect(face.skinTone == SIMD4(200, 150, 100, 255))
        #expect(face.skin == ESSRefID(kind: .default, value: 0xD64))
        #expect(face.headParts == [ESSRefID(kind: .default, value: 0x51)])
        #expect(face.morphs == [0.5])
        #expect(face.presets == [3])
    }

    @Test func actorBaseAttributesBlockLaterFields() throws {
        let change = try ESSActorBaseChange(ESSChangeForm(
            form: ESSActorBaseChange.playerBase, flags: Base.baseData | Base.attributes | Base.race,
            typeIndex: 9, version: 74, data: ESSChangeFormData(stored: Data(count: 40))
        ))
        #expect(change.status == .partial(blockedBy: "ACTOR_BASE_ATTRIBUTES"))
        #expect(change.race == nil)
        #expect(change.level == 0)
    }
}
