// The HUD's pure rules: prompt text, compass values, frame refresh, and scale.

@testable import OpenSkyFormatsESM
@testable import OpenSkyMenus
@testable import OpenSkyWorldInterface
import simd
import Testing

struct HUDCoreTests {
    static func target(reference: UInt32 = 1, position: SIMD3<Float> = [0, 10, 0])
        -> InteractionTarget
    {
        let interaction = PlacedInteraction(
            reference: FormID(reference),
            base: FormID(2),
            position: position,
            name: "Test Door",
            action: .open,
            actionLabel: "Open",
            sounds: nil
        )
        return InteractionTarget(interaction: interaction, hitPosition: position, distance: 10)
    }

    @Test
    func promptJoinsActionAndName() {
        #expect(HUDCore.prompt(for: Self.target()) == "Open Test Door")
        #expect(HUDCore.prompt(for: nil) == nil)
    }

    @Test
    func headingIsNormalizedDegrees() {
        #expect(HUDCore.headingDegrees(-.pi / 2) == 270)
        #expect(HUDCore.headingDegrees(0) == 0)
    }

    @Test
    func markerPointsFromCameraToTarget() throws {
        let marker = try #require(HUDCore.markers(for: Self.target(), cameraPosition: .zero).first)
        #expect(abs(marker.headingDegrees - 90) < 0.001)
        #expect(marker.kind == .location)
    }

    @Test
    func markerIsDroppedWhenCameraStandsOnTarget() {
        let target = Self.target(position: [5, 5, 100])
        #expect(HUDCore.markers(for: target, cameraPosition: [5, 5, 0]).isEmpty)
    }

    @Test
    func disabledSettingsHidePromptAndMarkers() {
        var settings = HUDSettings()
        settings.promptEnabled = false
        settings.markersEnabled = false
        #expect(HUDCore.effectivePrompt(settings, target: Self.target()) == nil)
        #expect(HUDCore.effectiveMarkers(settings, target: Self.target(), cameraPosition: .zero)
            .isEmpty)
    }

    @Test
    func frameUpdateSendsOnlyWhatChanged() {
        var sync = HUDSyncState()
        sync.lastCameraPosition = .zero
        sync.lastHeadingDegrees = 90
        let idle = HUDCore.frameUpdate(
            sync: sync, hasTarget: true, cameraPosition: .zero, heading: 90
        )
        #expect(idle.isEmpty)

        let moved = HUDCore.frameUpdate(
            sync: sync, hasTarget: true, cameraPosition: [1, 0, 0], heading: 90
        )
        #expect(moved == HUDFrameUpdate(prompt: false, markers: true, heading: false))

        let movedWithoutTarget = HUDCore.frameUpdate(
            sync: sync, hasTarget: false, cameraPosition: [1, 0, 0], heading: 45
        )
        #expect(movedWithoutTarget == HUDFrameUpdate(prompt: false, markers: false, heading: true))
    }

    @Test
    func scaleIsClampedAndFinite() {
        #expect(HUDCore.clampedScale(5) == 2)
        #expect(HUDCore.clampedScale(0.1) == 0.5)
        #expect(HUDCore.clampedScale(.nan) == 1)
        #expect(HUDCore.clampedScale(1.25) == 1.25)
    }
}
