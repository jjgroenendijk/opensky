// Spawned references and loose items through the real `CellSceneBuilder`
// (issue #177, roadmap item 12.1.3): an authored item reference resolves a
// model, a collision shape and a `.take` interaction, and a dropped object
// synthesized from world state does all three at its placement.
//
// Synthetic ESM + NIF bytes only; no game content.

import Foundation
@testable import opensky
import simd
import Testing

extension CellSceneBuilderTests {
    // MARK: - Fixtures

    /// The exterior cell every build in this file targets.
    static var spawnCell: CellSceneLocation {
        .exterior(CellCoordinate(x: 6, y: -2))
    }

    /// A snapshot holding one spawned object, keyed the way the store keys a
    /// runtime-created reference.
    func spawnState(
        sequence: UInt64 = 1,
        base: UInt32,
        position: SIMD3<Float>,
        scale: Float = 1,
        count: Int32 = 1,
        location: CellSceneLocation = CellSceneBuilderTests.spawnCell,
        deltas extra: [WorldStateComponentKind: WorldStateComponentValue] = [:]
    ) -> WorldStateSnapshot {
        var components = extra
        components[.spawn] = ReferenceSpawnState(
            base: FormID(base),
            location: location,
            placement: PlacedReference.Placement(position: position, rotation: .zero),
            scale: scale,
            count: count
        ).erased
        return WorldStateSnapshot(
            entries: [WorldStateSnapshotEntry(
                key: .generated(sequence),
                delta: ReferenceStateDelta(components: components, cell: location)
            )],
            nextGeneratedSequence: sequence + 1,
            sequence: 1
        )
    }

    /// A plugin with one MISC base and, optionally, one authored REFR placing
    /// it. Item bases carry the same EDID/FULL/MODL shape MSTT does, which is
    /// why `modelBaseRecord` builds them unchanged.
    func itemPlugin(
        placedItem: Data = Data(),
        displayName: String? = "Iron Sword"
    ) -> Data {
        plugin(
            temporaryRefs: placedItem,
            modelBaseRecords: [
                "MISC": modelBaseRecord(
                    type: "MISC",
                    formID: 0x100,
                    modelPath: "arch\\solid.nif",
                    displayName: displayName
                )
            ]
        )
    }

    // MARK: - Loose items are first-class

    /// Before this issue a MISC base was not in `ModelBase.supportedTypes`, so
    /// its placed reference counted as an unsupported base and drew nothing.
    @Test(.enabled(if: Self.hasDevice))
    func placedItemReferenceDrawsAndOffersTake() throws {
        try writeLooseFile("meshes/arch/solid.nif", collisionRenderNIF())
        let scene = try build(pluginData: itemPlugin(
            placedItem: refrRecord(formID: 0x200, base: 0x100, position: SIMD3(10, 20, 30))
        ))

        #expect(scene.summary.drawnRefCount == 1)
        #expect(scene.summary.unsupportedBaseSkipCount == 0)
        #expect(instanceTranslations(scene) == [SIMD3(10, 20, 30)])
        let interaction = try #require(scene.interactions[FormID(0x200)])
        #expect(interaction.action == .take)
        // The HUD composes its prompt as label plus name, so this reads
        // "Take Iron Sword" without the section knowing what an item is.
        #expect(interaction.actionLabel == "Take")
        #expect(interaction.name == "Iron Sword")
        #expect(scene.staticCollision.shapes.contains { $0.reference == FormID(0x200) })
    }

    // MARK: - Spawned references

    @Test(.enabled(if: Self.hasDevice))
    func spawnedReferenceRendersAndCollidesAtItsPlacement() throws {
        try writeLooseFile("meshes/arch/solid.nif", collisionRenderNIF())
        let pluginData = itemPlugin()
        #expect(try build(pluginData: pluginData).summary.drawnRefCount == 0)

        let scene = try build(
            pluginData: pluginData,
            state: spawnState(base: 0x100, position: SIMD3(400, 500, 600))
        )
        #expect(scene.summary.spawnedRefCount == 1)
        #expect(scene.summary.drawnRefCount == 1)
        #expect(scene.summary.referenceAccountingIsExact)
        #expect(instanceTranslations(scene) == [SIMD3(400, 500, 600)])

        // Mesh and collision come off the same effective reference array, so a
        // spawned object is solid exactly where it is drawn.
        let spawned = FormID(0xFF00_0001)
        let shape = try #require(
            scene.staticCollision.shapes.first { $0.reference == spawned }
        )
        let radius = NIFCollisionModel.havokToEngineScale
        #expect(abs(shape.bounds.min.x - (400 - radius)) < 0.01)
        #expect(abs(shape.bounds.max.z - (600 + radius)) < 0.01)

        // And it is takeable again, with its stack count carried on the
        // synthesized REFR exactly as an authored XCNT would be.
        let interaction = try #require(scene.interactions[spawned])
        #expect(interaction.action == .take)
        let entry = try #require(scene.references[.generated(1)])
        #expect(entry.placedReference?.itemCount == 1)
        #expect(entry.isPersistent)
    }

    @Test(.enabled(if: Self.hasDevice))
    func spawnedReferenceCarriesItsStackCountAndScale() throws {
        try writeLooseFile("meshes/arch/solid.nif", collisionRenderNIF())
        let scene = try build(
            pluginData: itemPlugin(),
            state: spawnState(base: 0x100, position: .zero, scale: 3, count: 7)
        )
        let entry = try #require(scene.references[.generated(1)])
        #expect(entry.placedReference?.itemCount == 7)
        #expect(entry.placedReference?.scale == 3)
    }

    /// A spawn naming a different cell belongs to that cell, not to this one:
    /// dropping something in Whiterun must not make it appear in Riverwood.
    @Test(.enabled(if: Self.hasDevice))
    func spawnInAnotherCellIsNotPlacedHere() throws {
        try writeLooseFile("meshes/arch/solid.nif", collisionRenderNIF())
        let scene = try build(
            pluginData: itemPlugin(),
            state: spawnState(
                base: 0x100,
                position: SIMD3(1, 2, 3),
                location: .exterior(CellCoordinate(x: 0, y: 0))
            )
        )
        #expect(scene.summary.spawnedRefCount == 0)
        #expect(scene.summary.drawnRefCount == 0)
        #expect(scene.references.isEmpty)
    }

    /// Runtime state resolves over a spawned object exactly as it does over an
    /// authored one, because both go through `applyRuntimeState` together.
    @Test(.enabled(if: Self.hasDevice))
    func runtimeStateAppliesToSpawnedReferencesToo() throws {
        try writeLooseFile("meshes/arch/solid.nif", collisionRenderNIF())
        let hidden = try build(
            pluginData: itemPlugin(),
            state: spawnState(
                base: 0x100,
                position: SIMD3(1, 2, 3),
                deltas: [.enableState: ReferenceEnableState.disabled.erased]
            )
        )
        #expect(hidden.summary.spawnedRefCount == 1)
        #expect(hidden.summary.drawnRefCount == 0)
        #expect(hidden.summary.runtimeDisabledSkipCount == 1)
        #expect(hidden.summary.referenceAccountingIsExact)

        let moved = try build(
            pluginData: itemPlugin(),
            state: spawnState(
                base: 0x100,
                position: SIMD3(1, 2, 3),
                deltas: [.transform: ReferenceTransformOverride(
                    position: SIMD3(70, 80, 90)
                ).erased]
            )
        )
        #expect(instanceTranslations(moved) == [SIMD3(70, 80, 90)])
    }
}
