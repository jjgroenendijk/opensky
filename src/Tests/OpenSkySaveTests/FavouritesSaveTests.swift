// FAVS chunk: the player's favourites keep their order and hotkeys through a save.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventoryInterface
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct FavouritesSaveTests {
    @Test func favouritesAndHotkeysSurvive() throws {
        let favourites = try #require(
            FavouritesState(items: [FormID(0x0001_2EB7), FormID(0x0003_EADE)])
                .binding(FormID(0x0003_EADE), to: 3)
        )
        let original = OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: .player, cell: OpenSkySaveFixture.whiterun,
                    components: [favourites.erased]
                )
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
        let data = OpenSkySaveFixture.encode(original)
        #expect(data.range(of: Data("FAVS".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        let restored = file.snapshot[.player]?.component(FavouritesState.self)
        #expect(restored?.items == favourites.items)
        #expect(restored?.hotkeys == [3: FormID(0x0003_EADE)])
    }
}
