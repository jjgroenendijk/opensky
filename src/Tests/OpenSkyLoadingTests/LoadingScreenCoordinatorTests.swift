// A door transition covers the view at once, shows the picked screen for the
// minimum time after the destination is ready, then fades and resumes the
// world. A fast travel picks once the destination is known and holds until the
// area is in. A forced screen holds until released. A drag and the stick turn
// and zoom the object by frame time.

import Foundation
import OpenSkyConditions
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyLoading
import OpenSkyRenderCore
import simd
import Testing

final class FakeLoadingWorld: LoadingScreenWorld {
    var presentationRecords: PresentationRecordStore?
    var frames: [LoadingCoverFrame?] = []
    var paused: [Bool] = []

    func loadingConditionContext() -> ConditionContext {
        ConditionContext()
    }

    func loadingText(of screen: ResolvedRecord<LoadScreen>) -> String? {
        screen.record.editorID
    }

    func presentLoadingCover(_ frame: LoadingCoverFrame?) {
        frames.append(frame)
    }

    func setLoadingPaused(_ paused: Bool) {
        self.paused.append(paused)
    }
}

@MainActor
struct LoadingScreenCoordinatorTests {
    private typealias Fixture = ESMFixture

    private static func world(extra: [Data] = []) throws -> FakeLoadingWorld {
        let screen = Fixture.recordBytes("LSCR", formID: 0x50, fields: [
            ("EDID", Fixture.zstring("LoadScreenDragon")), ("SNAM", Fixture.f32(2)),
            ("NNAM", Fixture.u32(0x60))
        ])
        let world = FakeLoadingWorld()
        world.presentationRecords = try PresentationRecordStore(
            plugins: [("Base.esm", Fixture.plugin(records: [screen] + extra))]
        )
        return world
    }

    @Test func aDoorFadesToBlackAfterItsWait() throws {
        let world = try Self.world()
        let loading = LoadingScreenCoordinator(world: world)

        loading.begin(at: 10, fadeSeconds: 0.4, fadeWait: 0.01)
        #expect(world.frames.last??.opacity == 0)
        #expect(world.frames.last??.drawsObject == false)
        loading.tick(time: 10.21)
        #expect(abs((world.frames.last??.opacity ?? 0) - 0.5) < 0.001)
        loading.tick(time: 10.41)
        #expect(world.frames.last == .some(LoadingScreenCoordinator.darkFrame))
        loading.tick(time: 10.5)
        #expect(world.frames.last == .some(LoadingScreenCoordinator.darkFrame))

        loading.destinationReady(location: nil, at: 10.6)
        #expect(world.frames.last??.drawsObject == true)
    }

    @Test func coversAtOnceAndHoldsTheMinimumAfterTheBuild() throws {
        let world = try Self.world()
        let loading = LoadingScreenCoordinator(world: world)

        loading.begin(at: 10)
        #expect(world.paused == [true])
        #expect(world.frames.last == .some(LoadingScreenCoordinator.darkFrame))

        loading.destinationReady(location: nil, at: 10.2)
        #expect(loading.session?.screen?.record.editorID == "LoadScreenDragon")
        #expect(world.frames.last??.text == "LoadScreenDragon")
        #expect(world.frames.last??.scale == 2)

        loading.tick(time: 10.2 + LoadingScreenSession.minimumSeconds + 0.1)
        #expect(world.frames.last??.drawsObject == false)
        loading
            .tick(time: 10.2 + LoadingScreenSession.minimumSeconds + LoadingScreenSession
                .fadeSeconds)
        #expect(world.frames.last == .some(nil))
        #expect(world.paused.last == false)
        #expect(!loading.isCovering)
    }

    @Test func aLoadShowsItsScreenUntilItFinishes() throws {
        let world = try Self.world()
        let loading = LoadingScreenCoordinator(world: world)

        loading.beginLoad(at: 0)
        #expect(world.paused == [true])
        #expect(world.frames.last??.text == "LoadScreenDragon")
        loading.tick(time: 30)
        #expect(world.frames.last??.drawsObject == true, "no fade before the load ends")

        loading.loadFinished(at: 30)
        loading.tick(time: 30 + LoadingScreenSession.fadeSeconds + 0.01)
        #expect(!loading.isCovering)
        #expect(world.paused.last == false)
    }

    @Test func aTravelPicksWhenTheDestinationIsKnownAndHoldsForTheArea() throws {
        let world = try Self.world()
        let loading = LoadingScreenCoordinator(world: world)

        loading.begin(at: 0)
        #expect(loading.isWaitingForDestination)
        loading.destinationKnown(location: nil, at: 2)
        #expect(!loading.isWaitingForDestination)
        #expect(world.frames.last??.text == "LoadScreenDragon")
        loading.tick(time: 20)
        #expect(world.frames.last??.drawsObject == true, "no fade before the area is in")

        loading.loadFinished(at: 20)
        loading.tick(time: 20 + LoadingScreenSession.fadeSeconds + 0.01)
        #expect(!loading.isCovering)
    }

    @Test func framesCarryTheCameraPathClock() throws {
        let world = try Self.world()
        let loading = LoadingScreenCoordinator(world: world)
        loading.beginLoad(at: 5)
        loading.tick(time: 7.5)
        #expect(world.frames.last??.elapsedSeconds == 2.5)
    }

    @Test func disabledLoadingScreensLeaveTheViewAlone() throws {
        let world = try Self.world()
        let loading = LoadingScreenCoordinator(world: world)
        loading.isEnabled = false
        loading.begin(at: 0)
        loading.destinationReady(location: nil, at: 1)
        #expect(world.frames.isEmpty)
    }

    @Test func forcedScreenHoldsUntilReleased() throws {
        let world = try Self.world()
        let loading = LoadingScreenCoordinator(world: world)

        #expect(!loading.force(editorID: "Missing", at: 0))
        #expect(loading.force(editorID: "LoadScreenDragon", at: 0))
        loading.tick(time: 100)
        #expect(world.frames.last??.drawsObject == true)
        loading.releaseForced(at: 100)
        loading.tick(time: 100 + LoadingScreenSession.fadeSeconds)
        #expect(!loading.isCovering)
    }

    @Test func aDragAndTheStickTurnAndZoomByFrameTime() throws {
        let world = try Self.world()
        let loading = LoadingScreenCoordinator(world: world)
        loading.beginLoad(at: 0)
        loading.drag(by: [100, 50])
        loading.tick(time: 0.05)
        // 100 px x 0.05 s x 0.02 rad, and 50 px x 0.05 s x 0.6.
        #expect(abs((loading.session?.turnRadians ?? 0) - 0.1) < 1e-5)
        #expect(abs((loading.session?.fieldOfView ?? 0) - 76.5) < 1e-4)
        loading.setStick([1, 1])
        loading.tick(time: 0.15)
        // The stick turns by -0.45 rad and zooms by -5 per second.
        #expect(abs((loading.session?.turnRadians ?? 0) - 0.055) < 1e-5)
        #expect(abs((loading.session?.fieldOfView ?? 0) - 76) < 1e-4)
        #expect(abs((world.frames.last??.fieldOfView ?? 0) - 76) < 1e-4)
        loading.setStick(.zero)
        loading.drag(by: [100, 0])
        loading.tick(time: 10)
        #expect(abs((loading.session?.turnRadians ?? 0) - 0.255) < 1e-5, "a stall counts 0.1 s")
    }

    @Test func aFirstLoadShowsOnlyMainMenuScreens() throws {
        let world = try Self.world(extra: [Fixture.recordBytes(
            "LSCR",
            formID: 0x51,
            flags: 0x400,
            fields: [
                ("EDID", Fixture.zstring("LoadScreenMenu")), ("NNAM", Fixture.u32(0x60))
            ]
        )])
        let loading = LoadingScreenCoordinator(world: world)
        loading.beginFirstLoad(at: 0)
        #expect(loading.session?.screen?.record.editorID == "LoadScreenMenu")
    }

    @Test func aLaterTipComesFromAScreenThatMayShow() throws {
        let world = try Self.world()
        let loading = LoadingScreenCoordinator(world: world)
        #expect(loading.nextTip() == nil)
        loading.beginLoad(at: 0)
        #expect(loading.nextTip() == "LoadScreenDragon")
    }
}
