// The `World > Player & Locomotion` destination's registry contract (issue
// #191), in its own file for the same reason the journal one is: the parent
// suite sits near the file-length limit.
//
// What is pinned here is the part of the destination a panel test cannot see —
// where the row sits, what it is called, and which of its controls the sidebar's
// override dot and "Reset all" act on.

@testable import opensky
import Testing

struct DestinationRegistryLocomotionTests {
    @Test @MainActor
    func theDestinationSitsUnderWorldWithItsOwnIdentity() throws {
        let descriptor = try #require(DestinationRegistry.destination(id: "playerLocomotion"))
        #expect(descriptor.title == "Player & Locomotion")
        #expect(descriptor.section == .world)
        #expect(descriptor.sidebarIdentifier == "Destination-playerLocomotion")
        #expect(descriptor.isWorldInspector)
        #expect(descriptor.showsGameView)

        // It sits directly under the launch destination, because the player is
        // what the launch destination's camera is looking at.
        let world = try #require(AppSidebarModel.groups().first { $0.section == .world })
        let ids = world.destinations.map(\.id)
        #expect(ids.firstIndex(of: "playerLocomotion") == 1)
    }

    /// A forced gait is the destination's one overridden-ness, and the
    /// sidebar's reset releases it. Sneaking, jumping and raising an event are
    /// world actions rather than settings, so none of them lights the dot.
    @Test @MainActor
    func onlyAForcedGaitCountsAsAnOverride() throws {
        let descriptor = try #require(DestinationRegistry.destination(id: "playerLocomotion"))
        let overrides = try #require(descriptor.overrides)
        let providers = FakeWorldProviders()
        let context = WorldPanelContext(providers: providers)

        #expect(!overrides.isOverridden(context))

        providers.isSneaking = true
        providers.requestJump()
        _ = providers.raiseLocomotionEvent(named: LocomotionGraphNames.jumpUp)
        #expect(!overrides.isOverridden(context), "a world action lit the override dot")

        providers.forcedLocomotionGait = .sprint
        #expect(overrides.isOverridden(context))

        overrides.resetToDefaults(context)
        #expect(!overrides.isOverridden(context))
        #expect(providers.forcedLocomotionGait == nil)
        // The reset releases the gait and nothing else: the player the user
        // deliberately put in a crouch stays there.
        #expect(providers.isSneaking)
    }

    /// Camera mode is claimed by `World > World`, not here, so switching modes
    /// lights exactly one dot.
    @Test @MainActor
    func cameraModeStaysTheWorldDestinationsOverride() throws {
        let providers = FakeWorldProviders()
        providers.movementMode = .thirdPerson
        let context = WorldPanelContext(providers: providers)
        let locomotion = try #require(
            DestinationRegistry.destination(id: "playerLocomotion")?.overrides
        )
        let world = try #require(DestinationRegistry.destination(id: "world")?.overrides)

        #expect(world.isOverridden(context))
        #expect(!locomotion.isOverridden(context))
    }
}
