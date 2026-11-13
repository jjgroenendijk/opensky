// Animated objects of the resident cells, for `ObjectBehaviorCoordinator`.

public import OpenSkyActorPresentation
import OpenSkyCells
import OpenSkyFormatsESM
public import OpenSkyObjectAnimation
public import simd

extension CellStreamer.PropSteps {
    /// Moves each graph object's collision with the model-frame bones its graph last posed.
    public func poseMovingCollision(bones: (UInt32) -> [simd_float4x4]?) {
        let collisions = streamer.interiorScene.map(\.doorCollision)
            ?? streamer.composition.cells.values.flatMap(\.doorCollision)
        for collision in collisions {
            guard let parts = collision.movingParts else { continue }
            let reference = collision.reference.rawValue
            streamer.sequenceDoorLeaves[reference] = bones(reference).flatMap(parts.deltas(posed:))
        }
    }

    /// The interior's animated objects, or those of every resident exterior cell.
    public func residentAnimatedObjects() -> [CellAnimatedObject] {
        let scenes = streamer.interiorScene.map { [$0] } ?? Array(streamer.composition.cells.values)
        return scenes.flatMap(\.animatedObjects)
    }

    /// The doors that open with mesh sequences, in the same scenes.
    public func residentSequenceDoors() -> [CellSequenceDoor] {
        let scenes = streamer.interiorScene.map { [$0] } ?? Array(streamer.composition.cells.values)
        return scenes.flatMap(\.sequenceDoors)
    }

    /// The placed meshes that play node controllers, in the same scenes.
    public func residentNodeAnimations() -> [CellNodeAnimation] {
        let scenes = streamer.interiorScene.map { [$0] } ?? Array(streamer.composition.cells.values)
        return scenes.flatMap(\.nodeAnimations)
    }

    /// The towed carts with turning wheels, in the same scenes.
    public func residentAnimatedVehicles() -> [CellAnimatedVehicle] {
        let scenes = streamer.interiorScene.map { [$0] } ?? Array(streamer.composition.cells.values)
        return scenes.flatMap(\.animatedVehicles)
    }
}
