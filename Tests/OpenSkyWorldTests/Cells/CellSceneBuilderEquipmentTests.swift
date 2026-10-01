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

@testable import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventoryInterface
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import simd
import Testing

extension CellSceneBuilderTests {
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
