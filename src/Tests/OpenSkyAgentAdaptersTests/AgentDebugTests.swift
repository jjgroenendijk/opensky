import Foundation

// Debug commands that name a reference fail before they reach a port when the reference
// is not loaded, and the clock commands reach the runtime state.

@testable import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyRenderCore
import OpenSkySessionTesting
import OpenSkyWorldInterface
import simd
import Testing

@MainActor
struct AgentDebugTests {
    private let host = AgentHost()
    private let world: AgentWorldAdapter

    init() {
        world = AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
    }

    private func failure(of command: AgentDebugCommand) -> AgentErrorCode? {
        do {
            switch try world.perform(command) {
            case let .done(result):
                if case let .failure(error) = result {
                    return error.code
                }
                return nil
            case .waiting:
                return nil
            }
        } catch {
            return error.code
        }
    }

    @Test func anEquipThatPutNothingOnFails() throws {
        try AgentItemsAdapter.requireEquipped(
            .equipped(item: "Iron Sword", target: "player", changed: true, unequipped: []),
            text: ""
        )
        #expect(throws: AgentFailure.self) {
            try AgentItemsAdapter.requireEquipped(.noEquipment, text: "No equipment.")
        }
    }

    @Test func actorCommandsNeedALoadedActor() {
        let commands: [AgentDebugCommand] = [
            .kill("14"), .resurrect("14"), .decapitate("14"), .drunk(reference: "14", drunk: true),
            .eyes(reference: "14", textureSet: "Eyes"),
            .setActorValue(reference: "14", name: "Health", value: 1),
            .modActorValue(reference: "14", name: "Health", delta: 1)
        ]
        for command in commands {
            #expect(failure(of: command) != nil, "\(command)")
        }
    }

    @Test func settingTheTimeMovesTheGameClock() {
        #expect(failure(of: .setTime(hour: 9)) == nil)
        #expect(host.fakeRuntimeState.setGameClockHourCalls == [9])
    }

    @Test func aGridTeleportStandsOnTheHigherOfTerrainAndCollision() {
        let collision = FakeCellStreamerCollisionPort()
        #expect(AgentTeleportJob.gridGround(at: .zero, in: collision) == nil)
        collision.sampleTerrainResult = TerrainGroundSample(height: -14112, normal: [0, 0, 1])
        #expect(AgentTeleportJob.gridGround(at: .zero, in: collision) == -14112)
        collision.topCollisionSurfaceResult = [0, 0, -2704]
        #expect(AgentTeleportJob.gridGround(at: .zero, in: collision) == -2704)
    }

    @Test func aTeleportTakesThePlayerOffACartSeatOnly() {
        let cart = ReferenceKey.plugin(name: "test.esp", objectID: 0x20)
        let horse = ReferenceKey.plugin(name: "test.esp", objectID: 0x21)
        let seated = [
            ReferenceKey.player: VehicleLink(carrier: cart, seat: .fixed(matrix_identity_float4x4))
        ]
        let mounted = [
            ReferenceKey.player: VehicleLink(carrier: horse, seat: .bone("SaddleBone"))
        ]

        #expect(AgentTeleportJob.sitsOnCart(.player, links: seated))
        #expect(!AgentTeleportJob.sitsOnCart(.player, links: mounted))
        #expect(!AgentTeleportJob.sitsOnCart(.player, links: [:]))

        let vehicles = FakeVehiclePort()
        let world = FakeVehicleWorldPort()
        world.vehicles = vehicles
        vehicles.core.links = mounted
        AgentTeleportJob.leaveCartSeat(vehicleWorld: world, session: nil)
        #expect(world.detachCalls.isEmpty)
        vehicles.core.links = seated
        AgentTeleportJob.leaveCartSeat(vehicleWorld: world, session: nil)
        #expect(world.detachCalls == [.player])
    }

    @Test func aFormConditionParameterTakesPlayerOrHex() throws {
        #expect(try AgentWorldAdapter.conditionParameter("player", isFormID: true) == 0x14)
        #expect(try AgentWorldAdapter.conditionParameter("Player", isFormID: true) == 0x14)
        #expect(try AgentWorldAdapter.conditionParameter("0001A2B3", isFormID: true) == 0x1A2B3)
        #expect(try AgentWorldAdapter.conditionParameter("14", isFormID: false) == 14)
        #expect(throws: AgentFailure.self) {
            try AgentWorldAdapter.conditionParameter("player", isFormID: false)
        }
    }

    @Test func aTeleportBeforeTheWorldLoadsIsRefused() {
        #expect(throws: AgentFailure.self) { try world.perform(.teleport(.position([0, 0, 0]))) }
    }

    @Test func anUnknownInputIsRefused() {
        #expect(throws: AgentFailure.self) { try world.applyInput("no such input", phase: .press) }
    }

    @Test func aWeatherCanBeForcedByItsFormID() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("SkyrimStormRain"))
        let plugin = ESMFixture.tes4()
            + ESMFixture.topGroup(
                "WTHR",
                contents: ESMFixture.record("WTHR", formID: 0xC8220, data: fields)
            )
        let session = FakeGameSessionPort()
        let weather = FakeWeatherSystemPort()
        weather.store = try WeatherStore(file: ESMFile(data: plugin))
        session.weather = weather
        host.gameSession = session
        guard case let .done(.success(answer)) = try world.perform(.weather("000C8220")) else {
            Issue.record("expected an answer")
            return
        }
        #expect(answer["forced"] == "SkyrimStormRain")
        #expect(weather.forceWeatherCalls.map(\.weather) == [FormID(0xC8220)])
    }

    private func view(weather: UInt32?) -> AgentDebugCommand {
        .view(AgentViewTarget(
            feet: [0, 0, 0], yawDegrees: 0, pitchDegrees: 0, worldspace: nil,
            interiorCell: nil, hour: nil, weather: weather
        ))
    }

    @Test func aViewWithAWeatherNoPluginHasIsRefused() {
        let session = FakeGameSessionPort()
        let weather = FakeWeatherSystemPort()
        weather.store = WeatherStore(loadOrder: LoadOrderPlugins([]))
        session.weather = weather
        host.gameSession = session
        #expect(failure(of: view(weather: 0x999)) == .invalidArgument)
        #expect(weather.forceWeatherCalls.isEmpty)
        // Without a weather the command goes on to the teleport, which needs a loaded world.
        #expect(failure(of: view(weather: nil)) != .invalidArgument)
    }
}
