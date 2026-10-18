// Which door the graph keeps when a cell names one reference twice, or when two
// cells name it: an interaction door replaces, a placed door only fills a gap.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyNavigation
import simd
import Testing

struct NavigationCellContentsTests {
    private static let cell = CellSceneLocation.exterior(CellCoordinate(x: 0, y: 0))
    private static let other = CellSceneLocation.exterior(CellCoordinate(x: 1, y: 0))
    private static let destination = FormID(0x0001_0000)

    private static func door(at x: Float, to destination: FormID? = nil) -> RuntimeNavigationDoor {
        RuntimeNavigationDoor(position: SIMD3(x, 0, 0), destination: destination)
    }

    private static func contents(
        interaction: [(reference: UInt32, door: RuntimeNavigationDoor)] = [],
        placed: [(reference: UInt32, door: RuntimeNavigationDoor)] = []
    ) -> NavigationCellContents {
        NavigationCellContents(
            stateSequence: 1, navmeshes: [], interactionDoors: interaction, placedDoors: placed
        )
    }

    @Test
    func interactionDoorWinsOverPlacedDoorInOneCell() {
        var graph = RuntimeNavigationGraph()
        graph.setCell(Self.cell, contents: Self.contents(
            interaction: [(7, Self.door(at: 10, to: Self.destination))],
            placed: [(7, Self.door(at: 20)), (8, Self.door(at: 30))]
        ))
        #expect(graph.door(FormID(7))?.position.x == 10)
        #expect(graph.door(FormID(8))?.position.x == 30)
        #expect(graph.hasTeleportDoors)
    }

    @Test
    func placedDoorKeepsAnotherCellsDoor() {
        var graph = RuntimeNavigationGraph()
        graph.setCell(Self.cell, contents: Self.contents(placed: [(7, Self.door(at: 10))]))
        graph.setCell(Self.other, contents: Self.contents(placed: [(7, Self.door(at: 20))]))
        #expect(graph.door(FormID(7))?.position.x == 10)
        graph.setCell(Self.other, contents: Self.contents(interaction: [(7, Self.door(at: 30))]))
        #expect(graph.door(FormID(7))?.position.x == 30)
    }

    @Test
    func removingTheCellDropsItsDoors() {
        var graph = RuntimeNavigationGraph()
        graph.setCell(Self.cell, contents: Self.contents(placed: [(8, Self.door(at: 30))]))
        graph.removeCell(Self.cell)
        #expect(graph.door(FormID(8)) == nil)
        #expect(graph.installedCells.isEmpty)
    }
}
