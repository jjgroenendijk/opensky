// The defaults a protocol requirement cannot carry: each short form forwards the
// arguments the renderer's own defaults were.

import Foundation
import OpenSkyEngineTesting
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyRenderCore
import OpenSkyRendering
import Testing

@MainActor
struct RendererPortDefaultsTests {
    private static func scene() throws -> SWFMovieScene {
        try SWFMovieScene(movie: SWFDisplayFixture.movie(tags: [SWFDisplayFixture.showFrameTag]))
    }

    @Test func theShortMovieFormsPassNoPreparation() throws {
        let port = try #require(FakeRendererPort())
        let movie = try Self.scene()
        #expect(try !port.startMenuMovie(movie))
        #expect(port.hadMenuMoviePreparation == [false])
        try port.setSWFOverlay(movie)
        #expect(port.swfOverlays.count == 1)
        try port.startSWFRuntime()
        #expect(port.swfRuntimeLimits == [.standard])
    }

    @Test func aMoviePictureIsLetterboxedByDefault() throws {
        let port = try #require(FakeRendererPort())
        let picture = MoviePicture(
            width: 2, height: 2, luma: Data(count: 4), chromaBlue: Data(count: 1),
            chromaRed: Data(count: 1), isFullRange: false
        )
        port.setMoviePicture(picture)
        #expect(port.moviePictures.map(\.letterbox) == [true])
    }

    @Test func theShortLoadingCoversFillTheRestWithNothing() throws {
        let port = try #require(FakeRendererPort())
        try port.setLoadingCover([])
        try port.setLoadingCover([], particles: [])
        try port.setLoadingCover(nil, lighting: RenderLighting(
            ambientColor: .zero, directionalAmbient: .black, directionalDirection: SIMD3(0, 0, -1),
            directionalColor: .one, fog: nil
        ))
        #expect(port.loadingCovers.map(\.hasLighting) == [false, false, true])
        #expect(port.loadingCovers.map(\.particleCount) == [0, 0, 0])
        #expect(port.loadingCovers.last?.placements == nil)
    }
}
