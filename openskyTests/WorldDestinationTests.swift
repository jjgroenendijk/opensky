// World-mode sidebar destination model (M7.1.2): Environment is the first
// destination and every case exposes a stable title + accessibility identifier
// that UI tests and later milestones depend on.

@testable import opensky
import Testing

struct WorldDestinationTests {
    @Test func environmentIsFirstDestination() {
        #expect(WorldDestination.allCases.first == .environment)
    }

    @Test func titlesAreHumanReadable() {
        #expect(WorldDestination.environment.title == "Environment")
        #expect(WorldDestination.uiLab.title == "UI Lab")
    }

    @Test func identifiersAreStableAndUnique() {
        #expect(WorldDestination.environment.sidebarIdentifier == "WorldDestination-environment")
        #expect(WorldDestination.uiLab.sidebarIdentifier == "WorldDestination-uiLab")
        let ids = WorldDestination.allCases.map(\.sidebarIdentifier)
        #expect(Set(ids).count == ids.count)
    }
}
