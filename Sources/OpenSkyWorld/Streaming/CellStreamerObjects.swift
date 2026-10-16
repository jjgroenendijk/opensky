// Animated objects of the resident cells, for `ObjectBehaviorCoordinator`.

extension CellStreamer {
    /// The interior's animated objects, or those of every resident exterior cell.
    public func residentAnimatedObjects() -> [CellAnimatedObject] {
        let scenes = interiorScene.map { [$0] } ?? Array(composition.cells.values)
        return scenes.flatMap(\.animatedObjects)
    }

    /// The doors that open with mesh sequences, in the same scenes.
    public func residentSequenceDoors() -> [CellSequenceDoor] {
        let scenes = interiorScene.map { [$0] } ?? Array(composition.cells.values)
        return scenes.flatMap(\.sequenceDoors)
    }

    /// The towed carts with turning wheels, in the same scenes.
    public func residentAnimatedVehicles() -> [CellAnimatedVehicle] {
        let scenes = interiorScene.map { [$0] } ?? Array(composition.cells.values)
        return scenes.flatMap(\.animatedVehicles)
    }
}
