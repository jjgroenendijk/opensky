// `Game.FadeOutGame`'s fader: the wait, the fade, the colour, and how it lays over
// the image space (<https://ck.uesp.net/wiki/FadeOutGame_-_Game>).

@testable import OpenSkyRenderCore
import simd
import Testing

struct ScreenFadeTests {
    @Test func aFadeOutWaitsThenCoversOverItsDuration() {
        var fade = ScreenFade()
        fade.start(fadingOut: true, black: true, delay: 1, duration: 2)
        #expect(fade.cover == 0)
        fade.advance(1)
        #expect(fade.cover == 0)
        fade.advance(1)
        #expect(abs(fade.cover - 0.5) < 0.0001)
        fade.advance(5)
        #expect(fade.cover == 1)
        #expect(!fade.isRunning)
        #expect(fade.fade == SIMD4(0, 0, 0, 1))
    }

    @Test func aFadeInShowsTheColourDuringItsWait() {
        var fade = ScreenFade()
        fade.start(fadingOut: false, black: false, delay: 2, duration: 1)
        #expect(fade.cover == 1)
        #expect(fade.colour == SIMD3(repeating: 1))
        fade.advance(2.5)
        #expect(abs(fade.cover - 0.5) < 0.0001)
        fade.advance(1)
        #expect(fade.cover == 0)
    }

    @Test func noDurationSwitchesAtTheEndOfTheWait() {
        var fade = ScreenFade()
        fade.start(fadingOut: true, black: true, delay: 0.5, duration: 0)
        #expect(fade.cover == 0)
        fade.advance(0.5)
        #expect(fade.cover == 1)
        fade.start(fadingOut: true, black: true, delay: -.infinity, duration: .nan)
        #expect(fade.cover == 1)
    }

    @Test func theFadeLaysOverTheModifiersUnlessALoadingScreenShows() {
        var state = ImageSpaceState()
        state.screenFade.start(fadingOut: true, black: false, delay: 0, duration: 0)
        #expect(state.current.fade == SIMD4(1, 1, 1, 1))
        #expect(state.current(withScreenFade: false).fade.w == 0)
    }
}
