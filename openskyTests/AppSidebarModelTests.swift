// Sidebar structure for the unified shell (issue #98 PR 2): sections group in
// declaration order, destinations keep registry order, empty sections drop,
// and launch selects the World destination. Pinned as unit assertions because make
// test-ui is blocked on the dev machine (TCC).

import AppKit
@testable import opensky
import Testing

struct AppSidebarModelTests {
    @Test
    func groupsFollowSectionAndRegistryOrder() {
        let groups = AppSidebarModel.groups()
        #expect(groups.map(\.section) == [.world, .developer, .library])
        #expect(
            groups[0].destinations.map(\.id)
                == [
                    "world", "environment", "hudInteraction", "systemMenu",
                    "inventoryMenu", "containerMenu", "audio", "runtimeState", "scripts"
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

    @Test @MainActor
    func destinationOverrideIndicatorRefreshesWithoutChangingSelection() throws {
        let sidebar = AppSidebarViewController()
        var overridden: Set<String> = []
        sidebar.isDestinationOverridden = { overridden.contains($0) }
        _ = sidebar.view
        sidebar.select(id: "world")

        #expect(try #require(sidebar.overrideIndicatorIsVisible(destinationID: "world")) == false)
        overridden.insert("world")
        sidebar.refreshOverrideIndicators()
        #expect(try #require(sidebar.overrideIndicatorIsVisible(destinationID: "world")) == true)

        overridden.remove("world")
        sidebar.refreshOverrideIndicators()
        #expect(try #require(sidebar.overrideIndicatorIsVisible(destinationID: "world")) == false)
    }
}
