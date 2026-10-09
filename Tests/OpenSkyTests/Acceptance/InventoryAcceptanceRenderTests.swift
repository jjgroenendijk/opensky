// Inventory acceptance, pixel half: each step that should change the screen
// does, by changed-pixel count. A fixed camera renders before and after; a
// fitted camera would move with the geometry. Needs Metal 4.

import EngineTesting
import FormatsTesting
import Foundation
import Metal
import MetalKit
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventoryInterface
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
@testable import OpenSkyWorldState
import simd
import TagsTesting
import Testing

@Suite(.tags(.acceptance, .gpu))
@MainActor
struct InventoryAcceptanceRenderTests {
    private static let width = 320
    private static let height = 240

    /// The item base the take and drop cases move, and the model it draws.
    private static let itemBase: UInt32 = 0x0000_0600
    private static let itemReference: UInt32 = 0x0000_0610
    private static let itemModel = "loot.nif"

    /// Head-on from the south, far enough out to clear the renderer's ten-unit
    /// near plane and close enough that the fixture geometry below covers a
    /// large share of the frame.
    private static let camera = SceneCamera(
        eye: SIMD3(0, -600, 140),
        target: SIMD3(0, 0, 140),
        sunDirection: DemoScene.sunDirection,
        sunColor: DemoScene.sunColor,
        ambientColor: DemoScene.ambientColor
    )

    // MARK: - Take and drop

    /// Taking the item removes its pixels and dropping puts them back. The
    /// taken frame must equal a cell that never held it, and the dropped frame
    /// a cell whose plugin placed it.
    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func takingRemovesTheItemsPixelsAndDroppingPutsThemBack() throws {
        let cells = try CellSceneFixture()
        try cells.writeLooseFile("meshes/\(Self.itemModel)", Self.triangleNIF(cells))
        let authored = Self.itemPlugin(cells)
        // The same plugin with no placed reference at all, so everything drawn
        // in the dropped frame came from world state rather than from the file.
        let bare = Self.itemPlugin(cells, placed: false)

        let placedScene = try cells.build(pluginData: authored)
        #expect(placedScene.summary.drawnRefCount == 1)
        let takenScene = try cells.build(
            pluginData: authored, state: Self.deletedState(Self.itemReference)
        )
        #expect(takenScene.summary.runtimeDeletedSkipCount == 1)
        #expect(takenScene.summary.drawnRefCount == 0)
        let bareScene = try cells.build(pluginData: bare)
        #expect(bareScene.summary.drawnRefCount == 0)
        let droppedScene = try cells.build(
            pluginData: bare,
            state: cells.spawnState(
                base: Self.itemBase,
                position: .zero,
                location: .exterior(CellCoordinate(x: 6, y: -2))
            )
        )
        #expect(droppedScene.summary.spawnedRefCount == 1)
        #expect(droppedScene.summary.drawnRefCount == 1)

        let placed = try Self.pixels(of: placedScene)
        let taken = try Self.pixels(of: takenScene)
        let empty = try Self.pixels(of: bareScene)
        let dropped = try Self.pixels(of: droppedScene)

        let takeDelta = Self.changedPixels(placed, taken)
        #expect(takeDelta >= Self.minimumChangedPixels, "the take changed nothing on screen")
        let dropDelta = Self.changedPixels(empty, dropped)
        #expect(dropDelta >= Self.minimumChangedPixels, "the drop changed nothing on screen")

        // The item left, rather than moving: what is on screen after the take
        // is exactly what a cell that never held it draws.
        #expect(Self.changedPixels(taken, empty) == 0)
        // And what the drop put back is exactly what the plugin's own
        // placement drew, so the same delta is measured in both directions.
        #expect(Self.changedPixels(dropped, placed) == 0)
        #expect(takeDelta == dropDelta)
    }

    // MARK: - Equip

    /// Equipping another body piece changes the silhouette. Equipping the
    /// outfit's own piece is the control: its frame matches the untouched
    /// actor, so the change comes from the piece, not the rebuild.
    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func theEquippedActorsSilhouetteChanges() throws {
        let cells = try CellSceneFixture()
        try cells.writeLooseFile("meshes/cuirass_m.nif", Self.triangleNIF(cells))
        try cells.writeLooseFile(
            "meshes/robes_m.nif", Self.triangleNIF(cells, halfWidth: 220, height: 320)
        )
        for name in ["torso_m", "sword"] {
            try cells.writeLooseFile("meshes/\(name).nif", Self.triangleNIF(cells))
        }
        let pluginData = cells.plugin(
            temporaryRefs: cells.achrRecord(formID: 0x900, base: 0x800),
            modelBaseRecords: cells.equipmentActorRecords(npc: 0x800)
        )

        let outfitted = try cells.build(pluginData: pluginData)
        #expect(outfitted.summary.actorDrawnCount == 1)
        let equipped = try cells.build(
            pluginData: pluginData,
            state: Self.equippedState(actor: 0x900, equipped: [0x320])
        )
        #expect(equipped.summary.actorDrawnCount == 1)
        #expect(equipped.assets.meshKeys.contains { $0.contains("robes_m.nif") })
        #expect(!equipped.assets.meshKeys.contains { $0.contains("cuirass_m.nif") })
        let reEquipped = try cells.build(
            pluginData: pluginData,
            state: Self.equippedState(actor: 0x900, equipped: [0x300])
        )

        let worn = try Self.pixels(of: outfitted)
        let swapped = try Self.pixels(of: equipped)
        #expect(
            Self.changedPixels(worn, swapped) >= Self.minimumChangedPixels,
            "the equip changed nothing on screen"
        )
        #expect(try Self.changedPixels(worn, Self.pixels(of: reEquipped)) == 0)
    }

    // MARK: - Rendering

    /// How many pixels a step has to move before it counts as visible. Well
    /// above the handful a rounding difference could touch, and far below the
    /// share of the frame the fixture geometry covers, so the number is a
    /// floor rather than a tuned value.
    private static let minimumChangedPixels = 500

    private static func pixels(of scene: CellScene) throws -> [UInt8] {
        let device = try #require(CellSceneFixture.device)
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: width, height: height), device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(view: view, scene: scene.renderScene, camera: camera)
        // Everything that would move between two frames is off, so a pixel that
        // differs differs because the world state did.
        renderer.actorAnimationsEnabled = false
        renderer.weatherEnabled = false
        renderer.particlesEnabled = false
        renderer.precipitationEnabled = false
        renderer.grassEnabled = false
        renderer.sunShadowsEnabled = false
        let texture = try renderer.renderOffscreen(width: width, height: height)
        return ShadowSceneFixture.readPixels(texture: texture)
    }

    private static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        guard lhs.count == rhs.count else { return max(lhs.count, rhs.count) / 4 }
        return stride(from: 0, to: lhs.count, by: 4).reduce(into: 0) { count, index in
            if lhs[index ..< index + 4] != rhs[index ..< index + 4] {
                count += 1
            }
        }
    }

    // MARK: - Fixtures

    /// One MISC base with a model, optionally placed by a reference. Both cases
    /// need the base either way: a spawned object resolves its model through
    /// the same index an authored reference does.
    private static func itemPlugin(
        _ cells: CellSceneFixture,
        placed: Bool = true
    ) -> Data {
        cells.plugin(
            temporaryRefs: placed
                ? cells.refrRecord(formID: itemReference, base: itemBase, position: .zero)
                : Data(),
            modelBaseRecords: [
                "MISC": cells.modelBaseRecord(
                    type: "MISC",
                    formID: itemBase,
                    modelPath: itemModel,
                    displayName: "Loot"
                )
            ]
        )
    }

    /// One upright triangle in the XZ plane, in game units. `unitNIF` is one
    /// unit across, inside the ten-unit near plane. The two body pieces differ
    /// in size so a swap changes the shape.
    private static func triangleNIF(
        _ cells: CellSceneFixture,
        halfWidth: Float = 120,
        height: Float = 180
    ) -> Data {
        NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1])),
            .init("BSTriShape", NIFFixture.bsTriShape(
                attributes: CellSceneFixture.staticAttributes,
                strideDwords: CellSceneFixture.staticStrideDwords,
                vertexRecords: [
                    SIMD3<Float>(-halfWidth, 0, 0),
                    SIMD3<Float>(halfWidth, 0, 0),
                    SIMD3<Float>(0, 0, height)
                ].map(cells.vertexRecord(position:)),
                triangles: [0, 1, 2]
            ))
        ])
    }

    private static func deletedState(_ objectID: UInt32) -> WorldStateSnapshot {
        WorldStateSnapshot(
            entries: [WorldStateSnapshotEntry(
                key: .plugin(name: "skyrim.esm", objectID: objectID),
                delta: ReferenceStateDelta(
                    components: [.deletion: ReferenceDeletionState.deleted.erased]
                )
            )],
            nextGeneratedSequence: 1,
            sequence: 1
        )
    }

    private static func equippedState(
        actor: UInt32,
        equipped: [UInt32]
    ) -> WorldStateSnapshot {
        WorldStateSnapshot(
            entries: [WorldStateSnapshotEntry(
                key: .plugin(name: "skyrim.esm", objectID: actor),
                delta: ReferenceStateDelta(components: [
                    .inventory: ReferenceInventoryState(
                        stacks: equipped.map { InventoryStack(item: FormID($0), count: 1) },
                        equipped: equipped.map(FormID.init(stored:))
                    ).erased
                ])
            )],
            nextGeneratedSequence: 1,
            sequence: 1
        )
    }
}
