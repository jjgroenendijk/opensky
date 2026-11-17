// A move names its worldspace, because a city world and Tamriel share grid coordinates.

import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyWorldState
import Testing

struct ReferenceRelocationTests {
    private static let square = CellSceneLocation.exterior(CellCoordinate(x: 40, y: -24))

    @Test func aMoveLandsOnlyInItsOwnWorldspace() {
        let moved = ReferenceRelocation(location: Self.square, worldspace: "RiftenWorld")
        #expect(moved.lands(in: Self.square, worldspace: "riftenworld"))
        #expect(!moved.lands(in: Self.square, worldspace: "Tamriel"))
        #expect(!moved.lands(in: Self.square, worldspace: nil))
        #expect(!moved.lands(
            in: .exterior(CellCoordinate(x: 41, y: -24)),
            worldspace: "RiftenWorld"
        ))
    }

    @Test func aMoveWithNoWorldspaceLandsInAnyOfThem() {
        let moved = ReferenceRelocation(location: Self.square)
        #expect(moved.lands(in: Self.square, worldspace: "Tamriel"))
        #expect(moved.lands(in: Self.square, worldspace: nil))
    }

    @Test func aReferenceMovedToTheCityLeavesTheSameSquareOfTamriel() {
        let moved = ReferenceRelocation(location: Self.square, worldspace: "RiftenWorld")
        let delta = ReferenceStateDelta(components: [.relocation: moved.erased], cell: Self.square)
        #expect(delta.relocatesAway(from: Self.square, worldspace: "Tamriel"))
        #expect(!delta.relocatesAway(from: Self.square, worldspace: "RiftenWorld"))
    }
}
