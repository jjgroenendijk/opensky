// MenuGapSweep: which movies count as menus, and which menus have a bridge.

import Foundation
@testable import OpenSkyMenus
import Testing

struct MenuGapSweepTests {
    @Test func onlyTopLevelInterfaceMoviesAreMenus() {
        #expect(MenuGapSweep.isMenuMovie("interface\\map.swf"))
        #expect(!MenuGapSweep.isMenuMovie("interface\\inventory components\\itemcard.swf"))
    }

    @Test func everyBridgedMovieIsALowercasedTopLevelMenu() {
        for path in MenuMovieBridges.moviePaths {
            #expect(path == path.lowercased())
            #expect(MenuGapSweep.isMenuMovie(path))
        }
    }

    @Test func aNewSweepCountsNoUnsetReads() {
        let sweep = MenuGapSweep()
        #expect(sweep.unsetReads == 0)
        #expect(sweep.unsetNameCount == 0)
    }
}
