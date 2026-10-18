import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyNavigation
import OpenSkyWorldInterface

extension RuntimeNavigationGraph {
    public mutating func setCell(_ location: CellSceneLocation, scene: CellScene) {
        setCell(location, contents: NavigationCellContents(scene: scene))
    }
}

extension NavigationCellContents {
    public init(scene: CellScene) {
        let interactionDoors = scene.interactions.values
            .filter { $0.action == .open }
            .map { interaction in
                (
                    reference: interaction.reference.rawValue,
                    door: RuntimeNavigationDoor(
                        position: interaction.position,
                        destination: scene.doors.first { $0.reference == interaction.reference }?
                            .destination.door
                    )
                )
            }
        let placedDoors = scene.doors.map { door in
            (
                reference: door.reference.rawValue,
                door: RuntimeNavigationDoor(
                    position: door.position,
                    destination: door.destination.door
                )
            )
        }
        self.init(
            stateSequence: scene.stateSequence,
            navmeshes: scene.navmeshes,
            interactionDoors: interactionDoors,
            placedDoors: placedDoors
        )
    }
}
