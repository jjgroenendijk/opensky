// Animated objects of the resident cells, for `ObjectBehaviorCoordinator`.

extension CellStreamer {
    /// The interior's animated objects, or those of every resident exterior cell.
    public func residentAnimatedObjects() -> [CellAnimatedObject] {
        let scenes = interiorScene.map { [$0] } ?? Array(composition.cells.values)
        return scenes.flatMap(\.animatedObjects)
    }
}
