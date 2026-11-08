// The menu movie pacer: frames follow the movie's rate, and a stall is capped.

@testable import OpenSkyMenus
import Testing

struct MenuMovieFramePacerTests {
    @Test func framesFollowTheMovieRate() {
        var pacer = MenuMovieFramePacer()
        // Steps of 1/64 s at 32 frames a second are exact in binary.
        #expect(pacer.ticks(at: 10, frameRate: 32) == 0)
        #expect(pacer.ticks(at: 10.015625, frameRate: 32) == 0)
        #expect(pacer.ticks(at: 10.03125, frameRate: 32) == 1)
        #expect(pacer.ticks(at: 10.125, frameRate: 32) == 3)
    }

    @Test func aStallIsCappedAndARateOfZeroFallsBack() {
        var pacer = MenuMovieFramePacer()
        _ = pacer.ticks(at: 0, frameRate: 30)
        #expect(pacer.ticks(at: 5, frameRate: 30) == MenuMovieFramePacer.maximumTicks)
        #expect(pacer.ticks(at: 5.125, frameRate: 0) == 3)
        #expect(pacer.ticks(at: 4, frameRate: 30) == 0)
    }
}
