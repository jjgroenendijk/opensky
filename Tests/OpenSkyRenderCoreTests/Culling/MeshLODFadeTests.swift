// A mesh detail level change cross-fades over one second.

@testable import OpenSkyRenderCore
import Testing

struct MeshLODFadeTests {
    @Test
    func aChangeFadesTheFinerTrianglesOverOneSecond() throws {
        var fade = MeshLODFade(level: 0)
        #expect(fade.fading == nil)
        fade = fade.stepped(toward: 1, seconds: 0.25)
        #expect(fade.drawnLevel == 1)
        let half = try #require(fade.fading)
        #expect(half.finer == 0)
        #expect(abs(half.dissolve - 0.25) < 1e-5)
        fade = fade.stepped(toward: 1, seconds: 0.75)
        #expect(fade.fading == nil)
        #expect(fade.drawnLevel == 1)
    }

    @Test
    func goingFinerFadesTheExtraTrianglesIn() throws {
        let fade = MeshLODFade(level: 2).stepped(toward: 1, seconds: 0.25)
        #expect(fade.drawnLevel == 2)
        let fading = try #require(fade.fading)
        #expect(fading.finer == 1)
        #expect(abs(fading.dissolve - 0.75) < 1e-5)
    }

    @Test
    func turningBackRunsTheRestInReverse() throws {
        let out = MeshLODFade(level: 0).stepped(toward: 1, seconds: 0.25)
        let back = out.stepped(toward: 0, seconds: 0)
        let fading = try #require(back.fading)
        #expect(back.level == 0)
        #expect(abs(fading.dissolve - 0.25) < 1e-5)
    }
}
