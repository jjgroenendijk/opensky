// Deterministic coverage for the UI Lab SWF bridge on GameViewController
// (M8.2.5). Runs against a synthetic BSA holding synthetic SWF blobs — never
// extracted game files (AGENTS.md "Legal & IP boundary") — so movie
// enumeration, decode, the tally snapshot, and the failure paths are all
// exercised without game data and without touching Metal (the bridge treats a
// nil renderer as "no GPU assignment", exactly as the other control bridges).

import AppKit
import Foundation
@testable import opensky
import Testing

struct GameViewControllerSWFLabTests {
    private let dataURL: URL

    init() throws {
        dataURL = FileManager.default.temporaryDirectory
            .appending(path: "opensky-swflab-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
    }

    /// A one-frame movie placing a solid rectangle: two PlaceObject2 tags so
    /// the tally is distinguishable from an empty timeline.
    private static func movieBytes() -> Data {
        var first = SWFDisplayFixture.Place2()
        first.depth = 1
        first.characterId = 1
        var second = SWFDisplayFixture.Place2()
        second.depth = 2
        second.characterId = 1
        second.matrix = SWFDisplayFixture.MatrixSpec(translateX: 2000, translateY: 1000)
        var fixture = SWFFixture()
        fixture.tags = [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 1,
                width: 2000,
                height: 2000,
                color: SWFColor(red: 255, green: 0, blue: 0, alpha: 255)
            ),
            SWFDisplayFixture.placeObject2Tag(first),
            SWFDisplayFixture.placeObject2Tag(second),
            SWFDisplayFixture.showFrameTag
        ]
        return fixture.build()
    }

    /// Mounts a synthetic archive holding the given `Interface\` movies.
    private func makeLoader(movies: [(name: String, data: Data)]) throws -> SWFMovieLoader {
        var fixture = BSAFixture()
        fixture.files = movies.map {
            BSAFixture.File(folder: "interface", name: $0.name, stored: $0.data)
        }
        let url = dataURL.appending(path: "swflab.bsa", directoryHint: .notDirectory)
        try fixture.build().write(to: url)
        return SWFMovieLoader(
            fileSystem: VirtualFileSystem(dataURL: dataURL, archiveURLs: [url])
        )
    }

    @MainActor
    private func makeController(
        movies: [(name: String, data: Data)]
    ) throws -> GameViewController {
        let controller = GameViewController()
        let loader = try makeLoader(movies: movies)
        controller.swfMovieLoaderFactory = { loader }
        return controller
    }

    @Test @MainActor
    func snapshotDegradesWithoutGameData() {
        let controller = GameViewController()
        #expect(controller.swfMoviePaths.isEmpty)
        let snapshot = controller.swfLabSnapshot
        #expect(!snapshot.installLoaded)
        #expect(snapshot.selectedPath == nil)
        #expect(snapshot.tally == nil)
        #expect(snapshot.drawStats == SWFDrawStats())
        #expect(SWFLabReadout.text(for: snapshot).contains("no game data"))
    }

    /// Enumerating movies walks every mounted archive index, so the 2 Hz panel
    /// readout must never repeat it.
    @Test @MainActor
    func moviePathsAreSortedAndEnumeratedOnce() throws {
        let controller = GameViewController()
        var builds = 0
        let loader = try makeLoader(movies: [
            ("zeta.swf", Self.movieBytes()), ("alpha.swf", Self.movieBytes())
        ])
        controller.swfMovieLoaderFactory = {
            builds += 1
            return loader
        }
        #expect(controller.swfMoviePaths == ["interface\\alpha.swf", "interface\\zeta.swf"])
        #expect(controller.swfMoviePaths.count == 2)
        _ = controller.swfLabSnapshot
        #expect(builds == 1, "loader built \(builds) times, expected once")
        #expect(controller.swfLabSnapshot.installLoaded)
    }

    @Test @MainActor
    func selectingAMovieRecordsItsFrameOneTally() throws {
        let controller = try makeController(movies: [("alpha.swf", Self.movieBytes())])
        controller.selectSWFMovie(path: "interface\\alpha.swf")

        let snapshot = controller.swfLabSnapshot
        #expect(snapshot.selectedPath == "interface\\alpha.swf")
        #expect(snapshot.loadError == nil)
        #expect(snapshot.tally?.placeObject2 == 2)
        #expect(snapshot.tally?.showFrames == 1)
        #expect(snapshot.tally?.danglingPlacements == 0)
        #expect(snapshot.unresolvedFontNames.isEmpty)
    }

    @Test @MainActor
    func clearingTheSelectionResetsTheSnapshot() throws {
        let controller = try makeController(movies: [("alpha.swf", Self.movieBytes())])
        controller.selectSWFMovie(path: "interface\\alpha.swf")
        controller.selectSWFMovie(path: nil)

        let snapshot = controller.swfLabSnapshot
        #expect(snapshot.selectedPath == nil)
        #expect(snapshot.tally == nil)
        #expect(snapshot.loadError == nil)
    }

    /// Malformed input must not crash the app: the error is reported in the
    /// readout and the previous selection is dropped.
    @Test @MainActor
    func undecodableMovieSurfacesTheErrorInsteadOfThrowing() throws {
        let controller = try makeController(movies: [
            ("alpha.swf", Self.movieBytes()),
            ("broken.swf", Data("not a swf container at all".utf8))
        ])
        controller.selectSWFMovie(path: "interface\\alpha.swf")
        controller.selectSWFMovie(path: "interface\\broken.swf")

        let snapshot = controller.swfLabSnapshot
        #expect(snapshot.selectedPath == "interface\\broken.swf")
        #expect(snapshot.tally == nil)
        let error = try #require(snapshot.loadError)
        #expect(!error.isEmpty)
        #expect(SWFLabReadout.text(for: snapshot).contains("[ERROR]"))
    }

    @Test @MainActor
    func missingMoviePathIsReportedNotFatal() throws {
        let controller = try makeController(movies: [("alpha.swf", Self.movieBytes())])
        controller.selectSWFMovie(path: "interface\\absent.swf")
        #expect(controller.swfLabSnapshot.loadError != nil)
    }

    /// Without a renderer the toggle reads the documented default (the SWF
    /// layer is on) and setting it is inert rather than a crash.
    @Test @MainActor
    func layerToggleIsInertWithoutARenderer() {
        let controller = GameViewController()
        #expect(controller.swfLayerEnabled)
        controller.swfLayerEnabled = false
        #expect(controller.swfLayerEnabled)
    }
}
