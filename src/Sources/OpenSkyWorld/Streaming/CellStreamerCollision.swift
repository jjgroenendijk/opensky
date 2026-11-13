// Ground, water, and collision queries against the resident cells.

import OpenSkyActorPresentation
import OpenSkyCells
public import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyRenderCore
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension CellStreamer.CollisionSteps {
    public func sampleTerrain(at position: SIMD2<Float>) -> TerrainGroundSample? {
        guard streamer.interiorScene == nil else { return nil }
        return streamer.composition.sampleTerrain(at: position)
    }

    /// Water-surface height for the locomotion bridge's swim test.
    public func sampleWaterHeight(at position: SIMD2<Float>) -> Float? {
        if let interiorScene = streamer.interiorScene {
            return [interiorScene.waterVolumes].water(at: SIMD3(
                position,
                CellSceneComposition.anyHeight
            ))?.surface
        }
        return streamer.composition.sampleWaterHeight(at: position)
    }

    /// The water at a point: its surface, its current, and its type.
    public func water(at point: SIMD3<Float>) -> WaterReading? {
        if let interiorScene = streamer.interiorScene {
            return [interiorScene.waterVolumes].water(at: point)
        }
        return streamer.composition.water(at: point)
    }

    /// Every collision candidate overlapping `bounds`: the per-cell static geometry
    /// plus the simulated bodies at their current pose, as ordinary placed shapes.
    /// Static shapes come first, for deterministic tie-breaks.
    public func collisionCandidates(
        overlapping bounds: ModelBounds
    ) -> [StaticCollisionShape] {
        staticCollisionCandidates(overlapping: bounds)
            + streamer.dynamicBodies.placedShapes(overlapping: bounds)
    }

    /// What a character's capsule collides with: the same, without the light clutter
    /// a character walks through.
    public func characterCollisionCandidates(
        overlapping bounds: ModelBounds
    ) -> [StaticCollisionShape] {
        staticCollisionCandidates(overlapping: bounds)
            + streamer.dynamicBodies.characterShapes(overlapping: bounds)
    }

    /// The immutable half alone, which is what the dynamic solver collides its
    /// bodies against — a body must not be handed itself as an obstacle.
    public func staticCollisionCandidates(
        overlapping bounds: ModelBounds
    ) -> [StaticCollisionShape] {
        fixedCollisionCandidates(overlapping: bounds)
            + vehicleCollisionCandidates(overlapping: bounds)
            + doorCollisionCandidates(overlapping: bounds)
    }

    /// A character's candidates but the vehicles' moving collision, for an actor that
    /// rides or pulls a vehicle.
    func collisionCandidatesIgnoringVehicles(
        overlapping bounds: ModelBounds
    ) -> [StaticCollisionShape] {
        fixedCollisionCandidates(overlapping: bounds)
            + doorCollisionCandidates(overlapping: bounds)
            + streamer.dynamicBodies.characterShapes(overlapping: bounds)
    }

    /// The nearest hit over every collision candidate, the per-cell trees walked
    /// along the ray. The same hit as `collisionCandidates(overlapping: ray.bounds)`.
    public func nearestCollisionHit(ray: InteractionRay) -> InteractionRayHit? {
        InteractionRaycaster.nearestHit(
            ray: ray,
            sets: fixedCollisionSets,
            shapes: vehicleCollisionCandidates(overlapping: ray.bounds)
                + doorCollisionCandidates(overlapping: ray.bounds)
                + streamer.dynamicBodies.placedShapes(overlapping: ray.bounds)
        )
    }

    /// Where a straight-down ray first meets fixed or door collision, for ground the
    /// terrain does not cover, such as a city cell that hides its terrain quadrants.
    public func topCollisionSurface(at position: SIMD2<Float>) -> SIMD3<Float>? {
        let column = ModelBounds(
            min: SIMD3(position - 0.01, -InteractionRaycaster.surfaceCeiling),
            max: SIMD3(position + 0.01, InteractionRaycaster.surfaceCeiling)
        )
        return InteractionRaycaster.topSurface(
            at: position,
            sets: fixedCollisionSets,
            shapes: doorCollisionCandidates(overlapping: column)
        )
    }

    /// Whether the static half, as `staticCollisionCandidates` holds it, blocks the ray.
    public func staticCollisionBlocks(ray: InteractionRay) -> Bool {
        InteractionRaycaster.hasHit(
            ray: ray,
            sets: fixedCollisionSets,
            shapes: vehicleCollisionCandidates(overlapping: ray.bounds)
                + doorCollisionCandidates(overlapping: ray.bounds)
        )
    }

    var fixedCollisionSets: [StaticCollisionSet] {
        streamer.interiorScene.map { [$0.staticCollision] } ?? streamer.composition
            .residentCollisionSets
    }

    func fixedCollisionCandidates(
        overlapping bounds: ModelBounds
    ) -> [StaticCollisionShape] {
        if let collision = streamer.interiorScene?.staticCollision {
            return collision.candidates(overlapping: bounds)
        }
        return streamer.composition.collisionCandidates(overlapping: bounds)
    }

    /// Each vehicle follower's collision at its live pose; at the build's pose until
    /// the vehicle pass first moves it.
    public func vehicleCollisionCandidates(
        overlapping bounds: ModelBounds
    ) -> [StaticCollisionShape] {
        let vehicles = streamer.interiorScene.map(\.vehicleCollision)
            ?? streamer.composition.cells.values.flatMap(\.vehicleCollision)
        return vehicles.flatMap { vehicle in
            vehicle.shapes(
                at: streamer.npcMovementState.vehiclePoses[vehicle.reference] ?? vehicle.placement,
                overlapping: bounds
            )
        }
    }

    /// Each sequence door's collision with its leaves where the door coordinator put them.
    public func doorCollisionCandidates(
        overlapping bounds: ModelBounds
    ) -> [StaticCollisionShape] {
        let doors = streamer.interiorScene.map(\.doorCollision)
            ?? streamer.composition.cells.values.flatMap(\.doorCollision)
        return doors.flatMap { door in
            door.shapes(
                leafDeltas: streamer.sequenceDoorLeaves[door.reference.rawValue],
                overlapping: bounds
            )
        }
    }
}
