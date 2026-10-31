// A door transition covers the view at once, shows the picked screen for the
// minimum time after the destination is ready, then fades and resumes the
// world. A fast travel picks once the destination is known and holds until the
// area is in. A forced screen holds until released.

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

    private static func world() throws -> FakeLoadingWorld {
        let screen = Fixture.recordBytes("LSCR", formID: 0x50, fields: [
            ("EDID", Fixture.zstring("LoadScreenDragon")), ("SNAM", Fixture.f32(2))
        ])
        let world = FakeLoadingWorld()
        world.presentationRecords = try PresentationRecordStore(
            plugins: [("Base.esm", Fixture.plugin(records: [screen]))]
        )
        return world
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

    @Test func objectStandsInFrontOfTheEye() {
        let frame = LoadingCoverFrame(
            model: "a.nif", scale: 1, rotationDegrees: .zero, translation: .zero,
            text: nil, opacity: 1, drawsObject: true
        )
        let transform = frame.objectTransform(eye: .zero, yaw: 0, pitch: 0, radius: 40)
        #expect(transform.columns.3.x == 100)
        #expect(transform.columns.3.y == 0)
    }

    @Test func cameraPathSetsTheDistanceWhenFartherThanTheFit() {
        let frame = LoadingCoverFrame(
            model: "a.nif", scale: 1, rotationDegrees: .zero, translation: [5, 0, -40],
            text: nil, opacity: 1, drawsObject: true
        )
        let transform = frame.objectTransform(
            eye: .zero, yaw: 0, pitch: 0, radius: 40, cameraOffset: [0, -300, 16]
        )
        // Yaw 0 looks down +X, so right is -Y and up is +Z.
        #expect(transform.columns.3.x == 300)
        #expect(transform.columns.3.y == -5)
        #expect(transform.columns.3.z == -56)
        let near = frame.objectTransform(
            eye: .zero, yaw: 0, pitch: 0, radius: 40, cameraOffset: [0, -25, 35]
        )
        #expect(near.columns.3.x == 100, "the fit wins over a near path")
    }

    @Test func coverLightComesFromAboveAndBehindTheEye() {
        let lighting = LoadingCoverFrame.lighting(yaw: 0, pitch: 0)
        #expect(lighting.directionalDirection.x > 0, "travels away from the eye")
        #expect(lighting.directionalDirection.z < 0, "travels down")
        #expect(lighting.fog == nil)
        #expect(lighting.ambientColor.x == lighting.ambientColor.z, "grey, not tinted")
    }

    @Test func objectStaysOnTheViewAxisWhenLookingDown() {
        let frame = LoadingCoverFrame(
            model: "a.nif", scale: 1, rotationDegrees: .zero, translation: .zero,
            text: nil, opacity: 1, drawsObject: true
        )
        let pitch: Float = -0.6
        let transform = frame.objectTransform(eye: .zero, yaw: 0.3, pitch: pitch, radius: 40)
        let center = SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
        let forward = SIMD3<Float>(cosf(pitch) * cosf(0.3), cosf(pitch) * sinf(0.3), sinf(pitch))
        #expect(simd_length(simd_cross(simd_normalize(center), forward)) < 1e-4)
        #expect(simd_dot(center, forward) > 0)
    }
}
