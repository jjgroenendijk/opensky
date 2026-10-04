// A door transition covers the view at once, shows the picked screen for the
// minimum time after the destination is ready, then fades and resumes the
// world. A forced screen holds until released.

import FormatsCoreTesting
import FormatsESMTesting
import Foundation
import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import simd
import Testing

final class FakeLoadingWorld: LoadingScreenWorld {
    var presentationRecords: PresentationRecordStore?
    var frames: [LoadingCoverFrame?] = []
    var paused: [Bool] = []
    var currentLocation: ResolvedFormID?

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
        let loading = LoadingScreenCoordinator()
        loading.attach(world: world)

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

    @Test func disabledLoadingScreensLeaveTheViewAlone() throws {
        let world = try Self.world()
        let loading = LoadingScreenCoordinator()
        loading.attach(world: world)
        loading.isEnabled = false
        loading.begin(at: 0)
        loading.destinationReady(location: nil, at: 1)
        #expect(world.frames.isEmpty)
    }

    @Test func forcedScreenHoldsUntilReleased() throws {
        let world = try Self.world()
        let loading = LoadingScreenCoordinator()
        loading.attach(world: world)

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
        let transform = frame.objectTransform(eye: .zero, yaw: 0, radius: 40)
        #expect(transform.columns.3.x == 100)
        #expect(transform.columns.3.y == 0)
    }
}
