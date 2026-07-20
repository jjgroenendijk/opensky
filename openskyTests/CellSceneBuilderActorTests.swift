// Actor streaming integration tests (milestone 5.5): ACHR discovery,
// worldspace-persistent position mapping, exact per-cell accounting
// (discovered = rendered + intentional skips + failures), interior actors.
// Synthetic plugin/NIF fixtures only, never extracted game files (AGENTS.md
// Legal & IP boundary).

import Metal
@testable import opensky
import simd
import Testing

extension CellSceneBuilderTests {
    // MARK: - Exterior accounting

    @Test(.enabled(if: Self.hasDevice)) func rendersResolvableActorAndAccountsExactly() throws {
        try writeLooseFile("meshes/torso_m.nif", unitNIF())
        let scene = try build(pluginData: plugin(
            temporaryRefs: achrRecord(formID: 0x900, base: 0x800),
            modelBaseRecords: actorChainRecords(npc: 0x800)
        ))
        #expect(scene.summary.actorCount == 1)
        #expect(scene.summary.actorDrawnCount == 1)
        #expect(scene.summary.actorFailureCount == 0)
        #expect(scene.summary.actorFailureReasons.isEmpty)
        #expect(scene.summary.actorAccountingIsExact)
        #expect(scene.summary.actorFailuresAreExplained)
        #expect(scene.summary.actorAnimatedCount == 0)
        #expect(scene.summary.actorAnimationFailureCount == 1)
        #expect(scene.summary.actorAnimationAccountingIsExact)
        #expect(scene.summary.actorAnimationFailuresAreExplained)
        #expect(scene.renderScene.instanceCount == 1)
        // The actor body key joins the cell's working set so streaming
        // eviction treats it exactly like a static's mesh.
        #expect(scene.assets.meshKeys.contains { $0.contains("torso_m.nif") })
    }

    @Test(.enabled(if: Self.hasDevice)) func initiallyDisabledActorIsExplicitSkip() throws {
        try writeLooseFile("meshes/torso_m.nif", unitNIF())
        let scene = try build(pluginData: plugin(
            temporaryRefs: achrRecord(formID: 0x900, base: 0x800, headerFlags: 0x0000_0800),
            modelBaseRecords: actorChainRecords(npc: 0x800)
        ))
        #expect(scene.summary.actorCount == 1)
        #expect(scene.summary.actorDrawnCount == 0)
        #expect(scene.summary.actorDisabledSkipCount == 1)
        #expect(scene.summary.actorAccountingIsExact)
        #expect(scene.renderScene.instanceCount == 0)
    }

    @Test(.enabled(if: Self.hasDevice)) func unresolvableActorBaseCountsFailed() throws {
        let scene = try build(pluginData: plugin(
            temporaryRefs: achrRecord(formID: 0x900, base: 0xDEAD)
        ))
        #expect(scene.summary.actorCount == 1)
        #expect(scene.summary.actorFailureCount == 1)
        #expect(scene.summary.actorAccountingIsExact)
        // 5.6 zero-unexplained rule: the counted failure carries its reason.
        #expect(scene.summary.actorFailuresAreExplained)
        #expect(scene.summary.actorFailureReasons.first?.contains("unresolved") == true)
    }

    @Test(.enabled(if: Self.hasDevice)) func malformedACHRCountsFailed() throws {
        let scene = try build(pluginData: plugin(
            temporaryRefs: achrRecord(formID: 0x900, base: 0x800, includePlacement: false)
        ))
        #expect(scene.summary.actorCount == 1)
        #expect(scene.summary.actorFailureCount == 1)
        #expect(scene.summary.actorAccountingIsExact)
        #expect(scene.summary.actorFailuresAreExplained)
        #expect(scene.summary.actorFailureReasons == ["ACHR 00000900: malformed record"])
    }

    @Test(.enabled(if: Self.hasDevice)) func deletedACHRIsNotDiscovered() throws {
        let scene = try build(pluginData: plugin(
            temporaryRefs: achrRecord(formID: 0x900, base: 0x800, headerFlags: 0x0000_0020)
        ))
        #expect(scene.summary.actorCount == 0)
        #expect(scene.summary.actorAccountingIsExact)
    }

    @Test(.enabled(if: Self.hasDevice)) func summaryLineReportsActorBuckets() throws {
        try writeLooseFile("meshes/torso_m.nif", unitNIF())
        let scene = try build(pluginData: plugin(
            temporaryRefs: achrRecord(formID: 0x900, base: 0x800)
                + achrRecord(formID: 0x901, base: 0x800, headerFlags: 0x0000_0800)
                + achrRecord(formID: 0x902, base: 0xDEAD),
            modelBaseRecords: actorChainRecords(npc: 0x800)
        ))
        #expect(scene.summary.summaryLine.hasSuffix(
            "3 actors (1 drawn, 1 disabled, 1 failed), 0 animated, 1 static"
        ))
    }

    // MARK: - Worldspace-persistent position mapping (door pattern)

    @Test(.enabled(if: Self.hasDevice)) func persistentActorMapsIntoOwningCellByPosition() throws {
        try writeLooseFile("meshes/torso_m.nif", unitNIF())
        // Cell (6,-2) spans x 24576..28672, y -8192..-4096.
        let scene = try build(pluginData: plugin(
            modelBaseRecords: actorChainRecords(npc: 0x800),
            extraWorldChildren: persistentActorCell(
                refs: achrRecord(
                    formID: 0x900, base: 0x800, position: SIMD3(25000, -6000, 10)
                )
            )
        ))
        #expect(scene.summary.actorCount == 1)
        #expect(scene.summary.actorDrawnCount == 1)
        #expect(scene.summary.actorAccountingIsExact)
    }

    @Test(.enabled(if: Self.hasDevice)) func persistentActorOutsideCellIsNotOwned() throws {
        try writeLooseFile("meshes/torso_m.nif", unitNIF())
        // Position lies in cell (7,-2) -> the (6,-2) build must not claim it.
        let scene = try build(pluginData: plugin(
            modelBaseRecords: actorChainRecords(npc: 0x800),
            extraWorldChildren: persistentActorCell(
                refs: achrRecord(
                    formID: 0x900, base: 0x800, position: SIMD3(29000, -6000, 10)
                )
            )
        ))
        #expect(scene.summary.actorCount == 0)
        #expect(scene.renderScene.instanceCount == 0)
    }

    // MARK: - Interiors

    @Test(.enabled(if: Self.hasDevice)) func interiorCellBuildsActors() throws {
        try writeLooseFile("meshes/torso_m.nif", unitNIF())
        let interiorID: UInt32 = 0x0001_38CA
        let bytes = plugin(
            modelBaseRecords: actorChainRecords(npc: 0x800),
            interiorRecords: interiorCellGroup(
                formID: interiorID,
                refs: achrRecord(formID: 0x900, base: 0x800)
            )
        )
        let device = try #require(Self.device)
        let builder = try makeBuilder(pluginData: bytes, device: device)
        let scene = try builder.buildInteriorScene(cellFormID: FormID(interiorID))
        #expect(scene.summary.actorCount == 1)
        #expect(scene.summary.actorDrawnCount == 1)
        #expect(scene.summary.actorAccountingIsExact)
        #expect(scene.summary.actorAnimationAccountingIsExact)
        #expect(scene.assets.meshKeys.contains { $0.contains("torso_m.nif") })
    }
}

// MARK: - Actor fixture builders

extension CellSceneBuilderTests {
    /// ACHR record bytes; headerFlags carries record-header bits (0x800
    /// initially disabled, 0x20 deleted — UESP record flags).
    func achrRecord(
        formID: UInt32,
        base: UInt32,
        position: SIMD3<Float> = .zero,
        headerFlags: UInt32 = 0,
        includePlacement: Bool = true
    ) -> Data {
        var name = Data()
        name.appendUInt32(base)
        var fields = ESMFixture.field("NAME", name)
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
    func actorChainRecords(npc: UInt32) -> [String: Data] {
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

    /// Worldspace persistent CELL at grid (0,0) holding cross-cell ACHRs in
    /// its persistent children group (door-handling storage pattern).
    func persistentActorCell(refs: Data) -> Data {
        let cellID: UInt32 = 0x41
        let cell = ESMFixture.record(
            "CELL",
            formID: cellID,
            data: cellFields(
                editorID: "PersistentActors",
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
        let subBlock = ESMFixture.exteriorBlock(
            x: 0, y: 0, groupType: 5, contents: cell + children
        )
        return ESMFixture.exteriorBlock(
            x: 0, y: 0, groupType: 4, contents: subBlock
        )
    }
}
