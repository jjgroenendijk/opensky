// Sidebar structure for the unified shell (issue #98 PR 2): sections group in
// declaration order, destinations keep registry order, empty sections drop,
// and launch selects the World destination. Pinned as unit assertions because make
// test-ui is blocked on the dev machine (TCC).

import AppKit
@testable import opensky
import Testing

@MainActor
struct AppSidebarModelTests {
    @Test
    func groupsFollowSectionAndRegistryOrder() {
        let groups = AppSidebarModel.groups()
        #expect(groups.map(\.section) == [.world, .developer, .library])
        #expect(
            groups[0].destinations.map(\.id)
                == [
                    "world", "playerLocomotion", "combatPhysics", "environment",
                    "hudInteraction", "systemMenu",
                    "inventoryMenu", "containerMenu", "inventoryEquipment", "audio",
                    "runtimeState", "scripts", "journal"
                ]
        )
        #expect(groups[1].destinations.map(\.id) == ["uiLab"])
        #expect(groups[2].destinations.map(\.id) == ["assetBrowser"])
    }

    @Test
    func emptySectionsAreDropped() {
        let worldOnly = DestinationRegistry.all.filter { $0.section == .world }
        let groups = AppSidebarModel.groups(from: worldOnly)
        #expect(groups.map(\.section) == [.world])
    }

    @Test
    func defaultSelectionIsTheWorldDestination() {
        let id = DestinationRegistry.defaultDestinationID
        #expect(id == "world")
        #expect(DestinationRegistry.destination(id: id) != nil)
    }

    @Test
    func sectionTitles() {
        #expect(SidebarSection.world.title == "World")
        #expect(SidebarSection.developer.title == "Developer")
        #expect(SidebarSection.library.title == "Library")
    }

    @Test
    func destinationOverrideIndicatorRefreshesWithoutChangingSelection() throws {
        let sidebar = AppSidebarViewController()
        var overridden: Set<String> = []
        sidebar.isDestinationOverridden = { overridden.contains($0) }
        _ = sidebar.view
        sidebar.select(id: "world")

        /// `as Bool?` is load-bearing: given a `Bool?`, `#require` cannot tell
        /// "unwrap this optional" from "check this boolean is true" and reports
        /// the requirement as ambiguous. Spelling the optional out picks the
        /// unwrapping overload.
        func indicatorIsVisible() throws -> Bool {
            try #require(sidebar.overrideIndicatorIsVisible(destinationID: "world") as Bool?)
        }

        #expect(try indicatorIsVisible() == false)
        overridden.insert("world")
        sidebar.refreshOverrideIndicators()
        #expect(try indicatorIsVisible() == true)

        overridden.remove("world")
        sidebar.refreshOverrideIndicators()
        #expect(try indicatorIsVisible() == false)
    }
}
