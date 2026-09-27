// Runtime world state applied during a cell build (issue #160): a transform
// override moves render and collision together, and a runtime-disabled or
// runtime-deleted reference leaves both. Synthetic ESM + NIF bytes only; no
// game content.

import Foundation
@testable import opensky
import simd
import Testing

extension CellSceneBuilderTests {
    // MARK: - Fixtures

    /// A snapshot holding one delta per listed object ID, keyed the way the
    /// builder keys the fixture plugin: no MAST entries in the header, so every
    /// record resolves to the plugin itself, lowercased by `ReferenceKey`.
    func runtimeState(
        _ deltas: [UInt32: ReferenceStateDelta],
        sequence: UInt64 = 1
    ) -> WorldStateSnapshot {
        let entries = deltas.keys.sorted().map { objectID in
            WorldStateSnapshotEntry(
                key: .plugin(name: "skyrim.esm", objectID: objectID),
                delta: deltas[objectID] ?? ReferenceStateDelta()
            )
        }
        return WorldStateSnapshot(
            entries: entries, nextGeneratedSequence: 1, sequence: sequence
        )
    }

    /// The world-space translation of every drawn instance, in draw order.
    func instanceTranslations(_ scene: CellScene) -> [SIMD3<Float>] {
        scene.renderScene.opaque.flatMap { group in
            group.instances.map { instance in
                let column = instance.modelMatrix.columns.3
                return SIMD3(column.x, column.y, column.z)
            }
        }
    }

    /// One collision-bearing plugin with a single REFR, so each test below
    /// differs only in the state it builds against.
    func collisionPlugin(position: SIMD3<Float>) -> Data {
        plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100, position: position),
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\solid.nif")
        )
    }

    // MARK: - Transform override

    @Test(.enabled(if: Self.hasDevice))
    func runtimeTransformOverrideMovesRenderAndCollisionTogether() throws {
        try writeLooseFile("meshes/arch/solid.nif", collisionRenderNIF())
        let pluginData = collisionPlugin(position: SIMD3(10, 20, 30))
        let authored = try build(pluginData: pluginData)
        #expect(instanceTranslations(authored) == [SIMD3(10, 20, 30)])

        let moved = try build(pluginData: pluginData, state: runtimeState([
            0x200: ReferenceStateDelta(components: [
                .transform: ReferenceTransformOverride(
                    position: SIMD3(500, 600, 700), scale: 2
                ).erased
            ])
        ]))
        #expect(instanceTranslations(moved) == [SIMD3(500, 600, 700)])
        #expect(moved.summary.drawnRefCount == 1)
        #expect(moved.summary.skippedRefCount == 0)
        // The collision shape has to follow the mesh, or a moved object is
        // solid where it used to stand: same sphere, same override placement,
        // and the override's scale of 2 doubles its extent.
        let shape = try #require(moved.staticCollision.shapes.first(where: {
            $0.reference == FormID(0x200)
        }))
        let radius = 2 * NIFCollisionModel.havokToEngineScale
        #expect(abs(shape.bounds.min.x - (500 - radius)) < 0.01)
        #expect(abs(shape.bounds.max.z - (700 + radius)) < 0.01)
        #expect(moved.stateSequence == 1)
    }

    // MARK: - Runtime enable state

    @Test(.enabled(if: Self.hasDevice))
    func runtimeDisabledReferenceLeavesRenderAndCollision() throws {
        try writeLooseFile("meshes/arch/solid.nif", collisionRenderNIF())
        let pluginData = collisionPlugin(position: SIMD3(10, 20, 30))
        let scene = try build(pluginData: pluginData, state: runtimeState([
            0x200: ReferenceStateDelta(components: [
                .enableState: ReferenceEnableState.disabled.erased
            ])
        ]))
        #expect(scene.renderScene.instanceCount == 0)
        #expect(scene.staticCollision.shapes.isEmpty)
        #expect(scene.summary.totalRefCount == 1)
        #expect(scene.summary.drawnRefCount == 0)
        #expect(scene.summary.runtimeDisabledSkipCount == 1)
        #expect(scene.summary.runtimeDeletedSkipCount == 0)
        #expect(scene.summary.skippedRefCount == 1)
        #expect(scene.summary.summaryLine.contains("1 skipped (1 runtime-disabled)"))
        // The object still exists at runtime, so it stays addressable in the
        // cell's reference index even though nothing drew it.
        #expect(scene.references.entry(for: FormID(0x200)) != nil)
    }

    // MARK: - Runtime deletion

    @Test(.enabled(if: Self.hasDevice))
    func runtimeDeletedReferenceLeavesRenderAndCollision() throws {
        try writeLooseFile("meshes/arch/solid.nif", collisionRenderNIF())
        let pluginData = collisionPlugin(position: SIMD3(10, 20, 30))
        let scene = try build(pluginData: pluginData, state: runtimeState([
            0x200: ReferenceStateDelta(components: [
                .deletion: ReferenceDeletionState.deleted.erased
            ])
        ]))
        #expect(scene.renderScene.instanceCount == 0)
        #expect(scene.staticCollision.shapes.isEmpty)
        #expect(scene.summary.drawnRefCount == 0)
        #expect(scene.summary.runtimeDeletedSkipCount == 1)
        #expect(scene.summary.runtimeDisabledSkipCount == 0)
        #expect(scene.summary.skippedRefCount == 1)
        #expect(scene.summary.summaryLine.contains("1 skipped (1 runtime-deleted)"))
    }

    // MARK: - Untouched references

    @Test(.enabled(if: Self.hasDevice))
    func stateForOtherReferencesLeavesThisCellAlone() throws {
        try writeLooseFile("meshes/arch/solid.nif", collisionRenderNIF())
        let scene = try build(
            pluginData: collisionPlugin(position: SIMD3(10, 20, 30)),
            state: runtimeState([
                0x999: ReferenceStateDelta(components: [
                    .deletion: ReferenceDeletionState.deleted.erased
                ])
            ])
        )
        #expect(instanceTranslations(scene) == [SIMD3(10, 20, 30)])
        #expect(scene.summary.skippedRefCount == 0)
        #expect(scene.staticCollision.shapes.count == 1)
    }
}
