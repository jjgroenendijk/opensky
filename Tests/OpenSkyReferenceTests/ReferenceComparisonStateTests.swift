// The comparison view's three modes and the flip between the games.

@testable import OpenSkyReference
import Testing

struct ReferenceComparisonStateTests {
    @Test func sideBySideShowsBothGames() {
        #expect(ReferenceComparisonState().images == [.opensky, .reference])
    }

    @Test func flipAgainSwapsTheGames() {
        var state = ReferenceComparisonState()
        state.select(.flip)
        #expect(state.images == [.opensky])
        state.select(.flip)
        #expect(state.images == [.reference])
        state.select(.flip)
        #expect(state.images == [.opensky])
    }

    @Test func differenceShowsOnePictureAndResetsTheFlip() {
        var state = ReferenceComparisonState()
        state.select(.flip)
        state.select(.flip)
        state.select(.difference)
        #expect(state.images == [.difference])
        #expect(!state.showsReference)
        #expect(state.caption.hasPrefix("Bright"))
    }
}
