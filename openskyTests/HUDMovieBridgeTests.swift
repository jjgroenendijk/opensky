// Vanilla HUD bridge coverage over a synthetic runtime. No game movie or
// extracted asset is used; the named display object and its entry points are
// installed in code.

import AppKit
@testable import opensky
import simd
import Testing

private final class HUDCallLog: @unchecked Sendable {
    private(set) var calls: [String: [[AS2Value]]] = [:]

    func append(_ name: String, arguments: [AS2Value]) {
        calls[name, default: []].append(arguments)
    }
}

private struct HUDHarness {
    let runtime: SWFMovieRuntime
    let target: SWFDisplayObject
    let log: HUDCallLog
}

struct HUDMovieBridgeTests {
    private static let entryPoints = [
        "SetCrosshairEnabled",
        "SetCrosshairTarget",
        "SetHealthMeterPercent",
        "SetMagickaMeterPercent",
        "SetStaminaMeterPercent",
        "SetCompassMarkers",
        "SetCompassAngle"
    ]

    private func makeRuntime() throws -> HUDHarness {
        let runtime = try SWFRuntimeFixture.started(tags: [
            SWFDisplayFixture.showFrameTag
        ])
        let target = SWFDisplayObject(content: .clip(nil))
        target.name = "HUDMovieBaseInstance"
        runtime.root.addChild(target, atDepth: 1)
        target.object.define(.integer(11), for: "CompassMarkerLocations")
        let log = HUDCallLog()
        for name in Self.entryPoints {
            AS2Natives.method(runtime.runtime, on: target.object, name: name) { context in
                log.append(name, arguments: context.arguments)
                return .undefined
            }
        }
        return HUDHarness(runtime: runtime, target: target, log: log)
    }

    @Test func initializationPublishesCrosshairMetersCompassAndEmptyPrompt() throws {
        let harness = try makeRuntime()
        try HUDMovieBridge.validate(runtime: harness.runtime)
        HUDMovieBridge.initialize(
            runtime: harness.runtime,
            meters: HUDMeterValues(health: 0.75, magicka: 0.5, stamina: 0.25),
            headingDegrees: -90
        )

        #expect(harness.log.calls["SetCrosshairEnabled"]?.first == [.boolean(true)])
        #expect(harness.log.calls["SetHealthMeterPercent"]?.first == [
            .number(0.75), .boolean(true)
        ])
        #expect(harness.log.calls["SetMagickaMeterPercent"]?.first == [
            .number(0.5), .boolean(true)
        ])
        #expect(harness.log.calls["SetStaminaMeterPercent"]?.first == [
            .number(0.25), .boolean(true)
        ])
        #expect(harness.log.calls["SetCompassAngle"]?.first == [
            .number(270), .number(270), .boolean(true)
        ])
        #expect(harness.log.calls["SetCrosshairTarget"]?.first?.first == .boolean(false))
    }

    @Test func validationRejectsAMovieWithoutTheHUDEntryPoints() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [
            SWFDisplayFixture.showFrameTag
        ])
        #expect(throws: HUDMovieError.missingDisplayObject(HUDMovieBridge.targetPath)) {
            try HUDMovieBridge.validate(runtime: runtime)
        }
    }

    @Test func compassMarkersUseTheObservedFlatFourValueContract() throws {
        let harness = try makeRuntime()
        HUDMovieBridge.setCompassMarkers(
            [
                HUDCompassMarker(
                    headingDegrees: -45,
                    opacityPercent: 80,
                    kind: .location,
                    scalePercent: 125
                )
            ],
            runtime: harness.runtime
        )
        HUDMovieBridge.setCompassHeading(450, runtime: harness.runtime)

        let array = try #require(
            harness.target.object.ownProperty("CompassTargetDataA")?.value.objectValue
        )
        #expect(array.arrayLength == 4)
        #expect(array.element(at: 0) == .number(315))
        #expect(array.element(at: 1) == .number(80))
        #expect(array.element(at: 2) == .number(11))
        #expect(array.element(at: 3) == .number(100))
        #expect(harness.log.calls["SetCompassMarkers"]?.count == 1)
        #expect(harness.log.calls["SetCompassAngle"]?.first == [
            .number(90), .number(90), .boolean(true)
        ])
    }

    @Test func elementVisibilityUsesObservedEntryPointsAndMeterClips() throws {
        let harness = try makeRuntime()
        for name in ["Health", "Magica", "Stamina"] {
            let meter = SWFDisplayObject(content: .clip(nil))
            meter.name = name
            let depth = UInt16(harness.target.children.count + 1)
            harness.target.addChild(meter, atDepth: depth)
        }
        let rollover = SWFDisplayObject(content: .editText(1))
        rollover.name = "RolloverInfoInstance"
        harness.target.addChild(rollover, atDepth: 10)
        let subtitles = SWFDisplayObject(content: .clip(nil))
        subtitles.name = "SubtitleTextHolder"
        harness.target.addChild(subtitles, atDepth: 11)

        HUDMovieBridge.setCrosshairEnabled(false, runtime: harness.runtime)
        HUDMovieBridge.setCompassHeading(
            90,
            visible: false,
            runtime: harness.runtime
        )
        HUDMovieBridge.setMetersEnabled(false, runtime: harness.runtime)
        HUDMovieBridge.setAuthoredPlaceholderTextEnabled(false, runtime: harness.runtime)

        #expect(harness.log.calls["SetCrosshairEnabled"]?.last == [.boolean(false)])
        #expect(harness.log.calls["SetCompassAngle"]?.last == [
            .number(90), .number(90), .boolean(false)
        ])
        for name in ["Health", "Magica", "Stamina"] {
            #expect(harness.target.child(named: name)?.isVisible == false)
        }
        #expect(!rollover.isVisible)
        #expect(!subtitles.isVisible)

        HUDMovieBridge.setAuthoredPlaceholderTextEnabled(true, runtime: harness.runtime)
        #expect(rollover.isVisible)
        #expect(subtitles.isVisible)
    }

    @Test func activationPromptMapsToTheVanillaTenArgumentCall() throws {
        let harness = try makeRuntime()
        HUDMovieBridge.setActivationPrompt("Open Test Door", runtime: harness.runtime)
        let arguments = try #require(harness.log.calls["SetCrosshairTarget"]?.first)

        #expect(arguments.count == 10)
        #expect(arguments[0] == .boolean(true))
        #expect(arguments[1] == .string("Open Test Door"))
        #expect(arguments[2] == .boolean(true))
        #expect(arguments[5] == .boolean(true))
    }

    @Test @MainActor
    func controllerBuildsPromptHeadingAndTargetMarker() throws {
        let interaction = PlacedInteraction(
            reference: FormID(1),
            base: FormID(2),
            position: SIMD3<Float>(0, 10, 0),
            name: "Test Door",
            action: .open,
            actionLabel: "Open"
        )
        let target = InteractionTarget(
            interaction: interaction,
            hitPosition: SIMD3<Float>(0, 10, 0),
            distance: 10
        )

        #expect(GameViewController.hudPrompt(for: target) == "Open Test Door")
        #expect(GameViewController.hudHeadingDegrees(-.pi / 2) == 270)
        let marker = try #require(
            GameViewController.hudMarkers(for: target, cameraPosition: .zero).first
        )
        #expect(abs(marker.headingDegrees - 90) < 0.001)
        #expect(marker.kind == .location)

        let controller = GameViewController()
        controller.updateHUDTarget(target)
        #expect(controller.hud.interactionTarget?.interaction.reference == FormID(1))
        #expect(controller.hud.promptNeedsUpdate)
        #expect(controller.hud.markersNeedUpdate)
    }
}
