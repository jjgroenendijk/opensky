// The cell-streamer fixture: cell coordinates, the synthetic built cell every
// streaming suite feeds through the manual build runner, and the streamer
// factory. The acceptance and real-data streaming suites drive a streamer built
// exactly this way.
//
// No Metal and no game data are involved.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import simd
import Testing

@MainActor
public enum CellStreamerFixture {
    public static func coordinate(_ x: Int32, _ y: Int32) -> CellCoordinate {
        CellCoordinate(x: x, y: y)
    }

    /// Synthetic built cell: empty draw list, optional bounds (so the first
    /// integrated cell can frame a camera) and asset keys (for eviction tests).
    public static func cellScene(
        bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? = (SIMD3(0, 0, 0), SIMD3(10, 10, 10)),
        meshKeys: Set<String> = [],
        textureKeys: Set<String> = [],
        location: CellSceneLocation? = nil,
        doors: [PlacedDoor] = [],
        interactions: [FormID: PlacedInteraction] = [:],
        staticCollision: StaticCollisionSet = .empty,
        triggerVolumes: TriggerVolumeSet = .empty,
        regions: [FormID] = [],
        acousticSpace: FormID? = nil,
        musicType: FormID? = nil,
        worldspaceMusicType: FormID? = nil,
        references: RuntimeReferenceIndex = .empty,
        stateSequence: UInt64 = 0,
        dynamicBodies: [DynamicBodyPlacement] = [],
        navmeshes: [Navmesh] = []
    ) -> CellScene {
        CellScene(
            renderScene: RenderScene(instances: []),
            summary: CellLoadSummary(
                cellName: "test", gridX: 0, gridY: 0,
                totalRefCount: 0, drawnRefCount: 0,
                unsupportedBaseSkipCount: 0, markerSkipCount: 0,
                modelFailureSkipCount: 0, malformedRefSkipCount: 0,
                modelCount: 0, textureCount: 0, missingTextureCount: 0
            ),
            bounds: bounds,
            location: location,
            doors: doors,
            interactions: interactions,
            regions: regions,
            acousticSpace: acousticSpace,
            musicType: musicType,
            worldspaceMusicType: worldspaceMusicType,
            staticCollision: staticCollision,
            triggerVolumes: triggerVolumes,
            dynamicBodies: dynamicBodies,
            navmeshes: navmeshes,
            references: references,
            stateSequence: stateSequence,
            assets: CellAssets(meshKeys: meshKeys, textureKeys: textureKeys)
        )
    }

    /// World center of cell (0,0); keeps the grid centered without recentering.
    public static let center = CellGridManager.cellCenter(of: coordinate(0, 0))

    public static func makeStreamer(
        runner: ManualCellBuildRunner,
        radius: Int32 = 1,
        sink: @escaping CellStreamer.SceneSink = { _, _ in }
    ) -> CellStreamer {
        CellStreamer(
            center: coordinate(0, 0), radius: radius, runner: runner, sink: sink
        )
    }
}

/// The placed-interaction, static-collision and interaction-ray builders the
/// walk-mode targeting suites share with the real-data interaction suites.
extension CellStreamerFixture {
    public static func interaction(
        reference: UInt32,
        base: UInt32 = 0x100,
        position: SIMD3<Float>,
        action: InteractionAction = .open,
        name: String = "Test Door",
        actionLabel: String = "Open",
        sounds: ModelBase.Sounds? = nil
    ) -> PlacedInteraction {
        PlacedInteraction(
            reference: FormID(reference),
            base: FormID(base),
            position: position,
            name: name,
            action: action,
            actionLabel: actionLabel,
            sounds: sounds
        )
    }

    public static func collision(
        reference: UInt32,
        position: SIMD3<Float>
    ) -> StaticCollisionSet {
        collisionSet(shapes: [collisionShape(reference: reference, position: position)])
    }

    public static func interactionRay(
        from origin: SIMD3<Float>,
        to target: SIMD3<Float>
    ) -> InteractionRay? {
        InteractionRay(origin: origin, direction: target - origin)
    }

    public static func collisionShape(
        reference: UInt32,
        position: SIMD3<Float>
    ) -> StaticCollisionShape {
        let extent = SIMD3<Float>(repeating: 1)
        return StaticCollisionShape(
            reference: FormID(reference),
            transform: MatrixMath.translation(position),
            geometry: .box(halfExtents: extent),
            bounds: ModelBounds(min: position - extent, max: position + extent)
        )
    }

    public static func collisionSet(
        shapes: [StaticCollisionShape]
    ) -> StaticCollisionSet {
        var stats = StaticCollisionStats()
        stats.shapeCount = shapes.count
        return StaticCollisionSet(
            location: nil,
            shapes: shapes,
            stats: stats
        )
    }
}

/// A placed door that teleports to `destination`.
extension CellStreamerFixture {
    public static func door(
        reference: UInt32,
        destination: UInt32,
        position: SIMD3<Float>
    ) -> PlacedDoor {
        PlacedDoor(
            reference: FormID(reference),
            position: position,
            destination: PlacedReference.TeleportDestination(
                door: FormID(destination),
                placement: PlacedReference.Placement(position: position, rotation: .zero),
                flags: []
            )
        )
    }
}
