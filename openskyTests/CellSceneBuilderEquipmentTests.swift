// Runtime equipment through a whole cell build (issue #178, roadmap item
// 12.2.1): an actor whose inventory component carries an equipped set is
// rebuilt wearing it, and an actor with no component still resolves from its
// plugin default outfit.
//
// This is the integration half of the acceptance. The unit tests prove the
// resolver honours an equipped set; this proves the set actually reaches it
// from a `WorldStateSnapshot`, through the same build path the streamer runs
// after `noteStateMutation`.
//
// Synthetic ESM + NIF bytes only, never extracted game files.

import Foundation
@testable import opensky
import simd
import Testing

extension CellSceneBuilderTests {
    /// The NPC chain of `actorChainRecords`, plus an OTFT default outfit
    /// (cuirass) and a second ARMO the runtime can equip instead (robes), plus
    /// a WEAP for the hand attachment.
    ///
    /// Slots: the skin torso ARMA, the cuirass and the robes all claim slot 32,
    /// so whichever piece is worn masks the skin and the other piece is simply
    /// not resolved.
    func equipmentActorRecords(npc: UInt32) -> [String: Data] {
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

    /// A snapshot giving one actor an inventory component with `equipped` worn.
    private func equippedState(actor: UInt32, equipped: [UInt32]) -> WorldStateSnapshot {
        runtimeState([
            actor: ReferenceStateDelta(components: [
                .inventory: ReferenceInventoryState(
                    stacks: equipped.map { InventoryStack(item: FormID($0), count: 1) },
                    equipped: equipped.map(FormID.init)
                ).erased
            ])
        ])
    }

    /// Every mesh key the built cell resolved, which is how a test names the
    /// models an actor ended up assembled from.
    private func meshKeys(_ scene: CellScene) -> Set<String> {
        scene.assets.meshKeys
    }

    // MARK: - Override

    @Test(.enabled(if: Self.hasDevice)) func untouchedActorWearsItsDefaultOutfit() throws {
        for name in ["cuirass_m", "robes_m", "torso_m", "sword"] {
            try writeLooseFile("meshes/\(name).nif", unitNIF())
        }
        let scene = try build(pluginData: plugin(
            temporaryRefs: achrRecord(formID: 0x900, base: 0x800),
            modelBaseRecords: equipmentActorRecords(npc: 0x800)
        ))

        #expect(scene.summary.actorDrawnCount == 1)
        #expect(meshKeys(scene).contains { $0.contains("cuirass_m.nif") })
        #expect(!meshKeys(scene).contains { $0.contains("robes_m.nif") })
        // The cuirass claims slot 32, so the skin torso stays masked.
        #expect(!meshKeys(scene).contains { $0.contains("torso_m.nif") })
    }

    @Test(.enabled(if: Self.hasDevice))
    func equippedSetOverridesTheDefaultOutfitOnRebuild() throws {
        for name in ["cuirass_m", "robes_m", "torso_m", "sword"] {
            try writeLooseFile("meshes/\(name).nif", unitNIF())
        }
        let pluginData = plugin(
            temporaryRefs: achrRecord(formID: 0x900, base: 0x800),
            modelBaseRecords: equipmentActorRecords(npc: 0x800)
        )

        let rebuilt = try build(
            pluginData: pluginData,
            state: equippedState(actor: 0x900, equipped: [0x320])
        )

        #expect(rebuilt.summary.actorDrawnCount == 1)
        #expect(meshKeys(rebuilt).contains { $0.contains("robes_m.nif") })
        #expect(!meshKeys(rebuilt).contains { $0.contains("cuirass_m.nif") })
        #expect(rebuilt.summary.actorAccountingIsExact)
    }

    @Test(.enabled(if: Self.hasDevice)) func strippedActorShowsItsSkinAgain() throws {
        for name in ["cuirass_m", "robes_m", "torso_m", "sword"] {
            try writeLooseFile("meshes/\(name).nif", unitNIF())
        }
        let scene = try build(
            pluginData: plugin(
                temporaryRefs: achrRecord(formID: 0x900, base: 0x800),
                modelBaseRecords: equipmentActorRecords(npc: 0x800)
            ),
            state: equippedState(actor: 0x900, equipped: [])
        )

        #expect(scene.summary.actorDrawnCount == 1)
        #expect(meshKeys(scene).contains { $0.contains("torso_m.nif") })
        #expect(!meshKeys(scene).contains { $0.contains("cuirass_m.nif") })
    }

    // MARK: - Attachment

    @Test(.enabled(if: Self.hasDevice)) func equippedWeaponJoinsTheActorsMeshes() throws {
        for name in ["cuirass_m", "robes_m", "torso_m", "sword"] {
            try writeLooseFile("meshes/\(name).nif", unitNIF())
        }
        let scene = try build(
            pluginData: plugin(
                temporaryRefs: achrRecord(formID: 0x900, base: 0x800),
                modelBaseRecords: equipmentActorRecords(npc: 0x800)
            ),
            state: equippedState(actor: 0x900, equipped: [0x300, 0x500])
        )

        #expect(scene.summary.actorDrawnCount == 1)
        #expect(meshKeys(scene).contains { $0.contains("cuirass_m.nif") })
        // The attachment caches under a bone-qualified key, so the same model
        // loaded as ordinary geometry stays a separate asset.
        #expect(meshKeys(scene).contains { $0.contains("sword.nif") && $0.contains("attach:") })
        // Cuirass plus sword: the weapon is a drawn instance of its own.
        #expect(scene.renderScene.instanceCount == 2)
    }

    /// A weapon whose model is missing costs the actor its sword and nothing
    /// else: the body still renders and the cell still accounts exactly.
    @Test(.enabled(if: Self.hasDevice)) func missingWeaponModelLeavesTheActorDrawn() throws {
        for name in ["cuirass_m", "robes_m", "torso_m"] {
            try writeLooseFile("meshes/\(name).nif", unitNIF())
        }
        let scene = try build(
            pluginData: plugin(
                temporaryRefs: achrRecord(formID: 0x900, base: 0x800),
                modelBaseRecords: equipmentActorRecords(npc: 0x800)
            ),
            state: equippedState(actor: 0x900, equipped: [0x300, 0x500])
        )

        #expect(scene.summary.actorDrawnCount == 1)
        #expect(scene.summary.actorAccountingIsExact)
        // The cuirass alone: nothing was drawn for the weapon. The mesh key is
        // deliberately not asserted on — `MeshLibrary` records a touched key
        // before it knows whether the file resolves, for every model it is
        // asked for, so absence there would not mean what it looks like.
        #expect(scene.renderScene.instanceCount == 1)
    }
}
