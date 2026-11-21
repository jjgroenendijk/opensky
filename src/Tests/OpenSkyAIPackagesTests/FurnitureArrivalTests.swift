// The arrival radius of a walk to furniture, and the turn to the seat's heading
// before the entry clip. Synthetic seats.

@testable import OpenSkyAIPackages
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyWorldInterface
import simd
import Testing

@MainActor
struct FurnitureArrivalTests {
    private static let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x500)
    private static let seat = PackageSeat(
        furniture: .plugin(name: "skyrim.esm", objectID: 0x900), index: 0,
        seat: FurnitureSeat(
            position: SIMD3(100, 0, 0), heading: .pi / 2,
            animationType: FurnitureSeat.sitAnimation, keyword: nil
        )
    )

    @Test func aWalkArrivesInsideTheLargerOfTheFurnitureAndAskedRadius() {
        let settings = FurnitureArrivalSettings.vanilla
        let seat = Self.seat.seat
        #expect(FurnitureArrival.hasArrived(
            feet: SIMD3(0, 0, 0), seat: seat, askedRadius: 0, settings: settings
        ))
        #expect(!FurnitureArrival.hasArrived(
            feet: SIMD3(-100, 0, 0), seat: seat, askedRadius: 0, settings: settings
        ))
        #expect(FurnitureArrival.hasArrived(
            feet: SIMD3(-100, 0, 0), seat: seat, askedRadius: 250, settings: settings
        ))
        #expect(!FurnitureArrival.hasArrived(
            feet: SIMD3(100, 0, 300), seat: seat, askedRadius: 0, settings: settings
        ))
    }

    @Test func theEntryWaitsForTheFurnitureAngle() {
        let settings = FurnitureArrivalSettings.vanilla
        let degree = Float.pi / 180
        #expect(!FurnitureArrival.mayEnter(
            remainingTurn: 30 * degree, seconds: 0, settings: settings
        ))
        #expect(FurnitureArrival.mayEnter(
            remainingTurn: -9 * degree, seconds: 0, settings: settings
        ))
        #expect(FurnitureArrival.mayEnter(remainingTurn: nil, seconds: 0, settings: settings))
        #expect(FurnitureArrival.mayEnter(
            remainingTurn: 2, seconds: FurnitureArrival.turnTimeout, settings: settings
        ))
    }

    @Test func theCoordinatorSeatsTheActorOnceItFacesTheSeat() {
        let world = FakePackageWorld()
        let coordinator = PackageCoordinator(world: world, data: nil)
        world.turnLeft = 1
        coordinator.seatTurns[Self.actor] = FurnitureSeatTurn(seat: Self.seat)
        coordinator.turnToSeat(Self.actor, by: 0.1)
        #expect(world.seatings.isEmpty)
        #expect(coordinator.seatTurns[Self.actor] != nil)
        world.turnLeft = 0.05
        coordinator.turnToSeat(Self.actor, by: 0.1)
        #expect(world.seatings == [Self.seat])
        #expect(coordinator.seatTurns[Self.actor] == nil)
    }

    @Test func aWalkWithNoSeatDoesNotCountAsReachedFurniture() {
        let coordinator = PackageCoordinator(world: FakePackageWorld(), data: nil)
        #expect(!coordinator.reachedFurniture(Self.actor))
    }

    @Test func theSettingsComeFromTheGameSettings() throws {
        let file = try GameSettingFixture.plugin(settings: [
            "fAIFurnitureDestinationRadius": .float(120),
            "fFurnitureMarkerAngleTolerance": .float(15)
        ])
        let settings = FurnitureArrivalSettings.resolve(
            store: GameSettingStore(plugins: [("F.esp", file)])
        )
        #expect(settings.destinationRadius == 120)
        #expect(abs(settings.angleToleranceRadians - 15 * .pi / 180) < 1e-5)
    }
}
