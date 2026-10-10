// Developer > Rendering Performance > Room Culling: the pinned ids, the switch, and
// the readout. Changing an id updates these literals in the same commit.

import AppKit
@testable import OpenSky
@testable import OpenSkyRendering
import Testing

@MainActor
struct RoomCullingSectionTests {
    @Test
    func theSwitchReachesTheProviderAndCountsAsAnOverride() {
        let providers = FakeWorldProviders()
        let section = RoomCullingSection()
        section.provider = providers
        section.loadViewIfNeeded()
        #expect(section.enabledControl.accessibilityIdentifier() == "RoomCullingEnabledControl")
        #expect(section.enabledControl.state == .on)
        #expect(!RoomCullingSection.isOverridden(provider: providers))

        section.enabledControl.state = .off
        section.enabledControl.sendAction(section.enabledControl.action, to: section)
        #expect(!providers.roomCullingEnabled)
        #expect(RoomCullingSection.isOverridden(provider: providers))
        RoomCullingSection.resetToDefaults(provider: providers)
        #expect(providers.roomCullingEnabled)
    }

    @Test
    func theReadoutCountsRoomsAndCulledInstances() {
        let providers = FakeWorldProviders()
        var snapshot = RenderPerformanceSnapshot()
        snapshot.roomCulling = RoomCullingReadout(
            rooms: 12, portals: 15, visibleRooms: 3, culledInstances: 240
        )
        providers.renderPerformanceSnapshot = snapshot
        let section = RoomCullingSection()
        section.provider = providers
        section.loadViewIfNeeded()
        section.refreshReadout()
        #expect(section.statsReadout == "Rooms: 12, portals: 15, 3 seen, instances culled: 240")
    }

    @Test
    func aSceneWithoutRoomsSaysSo() {
        #expect(RoomCullingSection.text(RoomCullingReadout()) == "Rooms: none")
        #expect(
            RoomCullingSection.text(RoomCullingReadout(rooms: 2, portals: 1))
                == "Rooms: 2, portals: 1, all drawn, instances culled: 0"
        )
    }
}
