// Actor streaming integration tests (milestone 5.5): ACHR discovery,
// worldspace-persistent position mapping, exact per-cell accounting
// (discovered = rendered + intentional skips + failures), interior actors.
// Synthetic plugin/NIF fixtures only, never extracted game files (AGENTS.md
// Legal & IP boundary).

@testable import FormatsCoreTesting
import FormatsESMTesting
import Metal
@testable import OpenSkyFormatsESM
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
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
