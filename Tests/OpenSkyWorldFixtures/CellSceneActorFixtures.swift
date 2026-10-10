// Actor and equipment records for the cell-scene fixture, shared by the world
// suites and the acceptance chains.

import Foundation
@testable import OpenSkyFormatsTesting
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd

extension CellSceneBuilderFixture {
    /// ACHR record bytes; headerFlags carries record-header bits (0x800
    /// initially disabled, 0x20 deleted — UESP record flags).
    public func achrRecord(
        formID: UInt32,
        base: UInt32,
        position: SIMD3<Float> = .zero,
        headerFlags: UInt32 = 0,
        includePlacement: Bool = true,
        enableParent: UInt32? = nil
    ) -> Data {
        var name = Data()
        name.appendUInt32(base)
        var fields = ESMFixture.field("NAME", name)
        fields += enableParentField(enableParent)
        if includePlacement {
            var data = Data()
            for value in [position.x, position.y, position.z, 0, 0, 0] {
                data.appendFloat32(value)
            }
            fields += ESMFixture.field("DATA", data)
        }
        return ESMFixture.record("ACHR", formID: formID, flags: headerFlags, data: fields)
    }

    /// Minimal resolvable appearance chain: NPC_ -> RACE (skin WNAM) ->
    /// ARMO -> ARMA with a male body model. Keys feed plugin()'s
    /// one-top-group-per-type layout. Race skeleton is intentionally absent
    /// on disk — a skeleton miss degrades, it never blocks the body.
    public func actorChainRecords(npc: UInt32) -> [String: Data] {
        var acbs = Data()
        acbs.appendUInt32(0)
        for _ in 0 ..< 7 {
            acbs.appendUInt16(0)
        }
        acbs.appendUInt16(0)
        acbs.appendUInt16(0)
        acbs.appendUInt16(0)
        let npcRecord = ESMFixture.record(
            "NPC_",
            formID: npc,
            data: ESMFixture.field("ACBS", acbs) + formIDField("RNAM", 0x100)
        )

        // RACE: WNAM skin, DATA (0x20 stat bytes + flags word, no FaceGen
        // head), MNAM + ANAM male skeleton path (UESP RACE).
        var raceData = Data(count: 0x20)
        raceData.appendUInt32(0x100)
        let raceRecord = ESMFixture.record(
            "RACE",
            formID: 0x100,
            data: formIDField("WNAM", 0x200)
                + ESMFixture.field("DATA", raceData)
                + ESMFixture.field("MNAM", Data())
                + ESMFixture.field("ANAM", ESMFixture.zstring("skel_m.nif"))
        )

        var bod2 = Data()
        bod2.appendUInt32(0b0100)
        bod2.appendUInt32(2)
        let armoRecord = ESMFixture.record(
            "ARMO",
            formID: 0x200,
            data: formIDField("RNAM", 0x19)
                + ESMFixture.field("BOD2", bod2)
                + formIDField("MODL", 0x210)
        )
        let armaRecord = ESMFixture.record(
            "ARMA",
            formID: 0x210,
            data: ESMFixture.field("BOD2", bod2)
                + formIDField("RNAM", 0x19)
                + ESMFixture.field("MOD2", ESMFixture.zstring("torso_m.nif"))
                + formIDField("MODL", 0x100)
        )
        return [
            "NPC_": npcRecord,
            "RACE": raceRecord,
            "ARMO": armoRecord,
            "ARMA": armaRecord
        ]
    }

    private func formIDField(_ type: String, _ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return ESMFixture.field(type, data)
    }

    /// Worldspace persistent CELL holding cross-cell `refs` in its persistent
    /// children group. Like Skyrim.esm, it sits directly in the world children
    /// (pass as `extraWorldChildren`) and carries XCLC (0,0) plus flag 0x400.
    public func persistentActorCell(
        refs: Data,
        cellID: UInt32 = 0x41,
        editorID: String = "PersistentActors"
    ) -> Data {
        let cell = ESMFixture.record(
            "CELL",
            formID: cellID,
            flags: 0x400,
            data: cellFields(
                editorID: editorID,
                grid: (0, 0),
                flags: 0,
                waterHeightBits: nil,
                waterType: nil
            )
        )
        let children = ESMFixture.childGroup(
            parent: cellID,
            groupType: 6,
            contents: ESMFixture.childGroup(parent: cellID, groupType: 8, contents: refs)
        )
        return cell + children
    }

    /// The NPC chain of `actorChainRecords`, plus an OTFT outfit (cuirass), a
    /// second ARMO to equip instead (robes), and a WEAP for the hand. The skin
    /// torso, cuirass and robes all claim slot 32, so the worn piece masks the
    /// skin and the other is not resolved.
    public func equipmentActorRecords(npc: UInt32) -> [String: Data] {
        var records = actorChainRecords(npc: npc)
        records["NPC_"] = npcWithOutfit(npc: npc, outfit: 0x400)

        var bod2 = Data()
        bod2.appendUInt32(0b0100)
        bod2.appendUInt32(2)

        func piece(armo: UInt32, arma: UInt32, model: String) -> (Data, Data) {
            let armoRecord = ESMFixture.record(
                "ARMO",
                formID: armo,
                data: equipmentFormID("RNAM", 0x19)
                    + ESMFixture.field("BOD2", bod2)
                    + equipmentFormID("MODL", arma)
            )
            let armaRecord = ESMFixture.record(
                "ARMA",
                formID: arma,
                data: ESMFixture.field("BOD2", bod2)
                    + equipmentFormID("RNAM", 0x19)
                    + ESMFixture.field("MOD2", ESMFixture.zstring(model))
                    + equipmentFormID("MODL", 0x100)
            )
            return (armoRecord, armaRecord)
        }

        let (cuirass, cuirassAA) = piece(armo: 0x300, arma: 0x310, model: "cuirass_m.nif")
        let (robes, robesAA) = piece(armo: 0x320, arma: 0x330, model: "robes_m.nif")
        records["ARMO"] = (records["ARMO"] ?? Data()) + cuirass + robes
        records["ARMA"] = (records["ARMA"] ?? Data()) + cuirassAA + robesAA

        var inam = Data()
        inam.appendUInt32(0x300)
        records["OTFT"] = ESMFixture.record(
            "OTFT", formID: 0x400, data: ESMFixture.field("INAM", inam)
        )

        var weaponData = Data()
        weaponData.appendUInt32(25)
        weaponData.appendFloat32(9)
        weaponData.appendUInt16(7)
        var dnam = Data([1, 0, 0, 0])
        dnam.append(Data(count: 96))
        records["WEAP"] = ESMFixture.record(
            "WEAP",
            formID: 0x500,
            data: ESMFixture.field("EDID", ESMFixture.zstring("TestSword"))
                + ESMFixture.field("MODL", ESMFixture.zstring("sword.nif"))
                + ESMFixture.field("DATA", weaponData)
                + ESMFixture.field("DNAM", dnam)
        )
        return records
    }

    private func npcWithOutfit(npc: UInt32, outfit: UInt32) -> Data {
        var acbs = Data()
        acbs.appendUInt32(0)
        for _ in 0 ..< 10 {
            acbs.appendUInt16(0)
        }
        return ESMFixture.record(
            "NPC_",
            formID: npc,
            data: ESMFixture.field("ACBS", acbs)
                + equipmentFormID("RNAM", 0x100)
                + equipmentFormID("DOFT", outfit)
        )
    }

    private func equipmentFormID(_ type: String, _ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return ESMFixture.field(type, data)
    }

    /// The world-space translation of every drawn instance, in draw order.
    public func instanceTranslations(_ scene: CellScene) -> [SIMD3<Float>] {
        scene.renderScene.opaque.flatMap { group in
            group.instances.map { instance in
                let column = instance.modelMatrix.columns.3
                return SIMD3(column.x, column.y, column.z)
            }
        }
    }
}
