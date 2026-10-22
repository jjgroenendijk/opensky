// World > Player & Locomotion > Mount: the registry wiring, the literal ids, the
// readout, and the two buttons reaching the provider.

import AppKit
@testable import OpenSky
import OpenSkyFormatsESM
import OpenSkyPlayer
import Testing

extension PlayerLocomotionPanelTests {
    @Test @MainActor
    func mountSectionIdsArePinned() throws {
        let panel = try Self.panel(providers: FakeWorldProviders())
        #expect(panel.mountSection.sectionIdentifier == "locomotionMount")
        #expect(
            panel.mountNearestControl.accessibilityIdentifier() == "LocomotionMountNearestControl"
        )
        #expect(panel.dismountControl.accessibilityIdentifier() == "LocomotionDismountControl")
        #expect(scriptsReadout("LocomotionMountStatsLabel", in: panel.view) != nil)
    }

    @Test @MainActor
    func readoutNamesTheMountAndThePhase() throws {
        let providers = FakeWorldProviders()
        let horse = ReferenceKey.generated(7)
        providers.mount.snapshot = MountControlSnapshot(
            readout: MountReadout(
                phase: .riding, mount: horse, kind: .horse, speed: 450, isSprinting: false,
                lastMount: horse, lastRefusal: nil, nearest: nil
            ),
            names: [horse: "Frost"]
        )
        let panel = try Self.panel(providers: providers)
        panel.mountSection.refreshReadout()
        let text = try #require(scriptsReadout("LocomotionMountStatsLabel", in: panel.view))
        #expect(text.contains("Mount: Frost (horse)"))
        #expect(text.contains("State: riding"))
        #expect(text.contains("Speed: 450"))
    }

    @Test @MainActor
    func buttonsReachTheProvider() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)
        panel.mountNearestControl.performClick(nil)
        panel.dismountControl.performClick(nil)
        #expect(providers.mount.mountNearestCalls == 1)
        #expect(providers.mount.dismountCalls == 1)
    }
}
