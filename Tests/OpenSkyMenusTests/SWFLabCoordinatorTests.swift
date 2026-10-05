// The UI Lab SWF section over a synthetic BSA of synthetic SWF blobs, never
// extracted game files. No world is attached, so there is no renderer.

import EngineTesting
import FormatsTesting
import Foundation
@testable import OpenSkyFormatsSWF
@testable import OpenSkyGameData
@testable import OpenSkyMenus
@testable import OpenSkyRendering
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct SWFLabCoordinatorTests {
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
    private func makeFiles(movies: [(name: String, data: Data)]) throws -> VirtualFileSystem {
        var fixture = BSAFixture()
        fixture.files = movies.map {
            BSAFixture.File(folder: "interface", name: $0.name, stored: $0.data)
        }
        let url = dataURL.appending(path: "swflab.bsa", directoryHint: .notDirectory)
        try fixture.build().write(to: url)
        return VirtualFileSystem(dataURL: dataURL, archiveURLs: [url])
    }

    @MainActor
    private static func makeLab(files: (any GameFileSource)? = nil) -> SWFLabCoordinator {
        let movies = SWFMovieSource(fileSystem: files, loadsImmediately: true)
        return SWFLabCoordinator(movies: movies, hud: HUDCoordinator(movies: movies))
    }

    @MainActor
    private func makeController(
        movies: [(name: String, data: Data)]
    ) throws -> SWFLabCoordinator {
        try Self.makeLab(files: makeFiles(movies: movies))
    }

    @Test @MainActor
    func snapshotDegradesWithoutGameData() {
        let lab = Self.makeLab()
        #expect(lab.moviePaths.isEmpty)
        let snapshot = lab.snapshot
        #expect(!snapshot.installLoaded)
        #expect(snapshot.selectedPath == nil)
        #expect(snapshot.tally == nil)
        #expect(snapshot.drawStats == SWFDrawStats())
        #expect(SWFLabReadout.text(for: snapshot).contains("no game data"))
    }

    @Test @MainActor
    func moviePathsAreSorted() throws {
        let lab = try Self.makeLab(files: makeFiles(movies: [
            ("zeta.swf", Self.movieBytes()), ("alpha.swf", Self.movieBytes())
        ]))
        #expect(lab.moviePaths == ["interface\\alpha.swf", "interface\\zeta.swf"])
        #expect(lab.moviePaths.count == 2)
        #expect(lab.snapshot.installLoaded)
    }

    @Test @MainActor
    func selectingAMovieRecordsItsFrameOneTally() throws {
        let lab = try makeController(movies: [("alpha.swf", Self.movieBytes())])
        lab.select(path: "interface\\alpha.swf")

        let snapshot = lab.snapshot
        #expect(snapshot.selectedPath == "interface\\alpha.swf")
        #expect(snapshot.loadError == nil)
        #expect(snapshot.tally?.placeObject2 == 2)
        #expect(snapshot.tally?.showFrames == 1)
        #expect(snapshot.tally?.danglingPlacements == 0)
        #expect(snapshot.unresolvedFontNames.isEmpty)
    }

    @Test @MainActor
    func clearingTheSelectionResetsTheSnapshot() throws {
        let lab = try makeController(movies: [("alpha.swf", Self.movieBytes())])
        lab.select(path: "interface\\alpha.swf")
        lab.select(path: nil)

        let snapshot = lab.snapshot
        #expect(snapshot.selectedPath == nil)
        #expect(snapshot.tally == nil)
        #expect(snapshot.loadError == nil)
    }

    /// Malformed input is reported in the readout, not thrown.
    @Test @MainActor
    func undecodableMovieSurfacesTheErrorInsteadOfThrowing() throws {
        let lab = try makeController(movies: [
            ("alpha.swf", Self.movieBytes()),
            ("broken.swf", Data("not a swf container at all".utf8))
        ])
        lab.select(path: "interface\\alpha.swf")
        lab.select(path: "interface\\broken.swf")

        let snapshot = lab.snapshot
        #expect(snapshot.selectedPath == "interface\\broken.swf")
        #expect(snapshot.tally == nil)
        let error = try #require(snapshot.loadError)
        #expect(!error.isEmpty)
        #expect(SWFLabReadout.text(for: snapshot).contains("[ERROR]"))
    }

    @Test @MainActor
    func missingMoviePathIsReportedNotFatal() throws {
        let lab = try makeController(movies: [("alpha.swf", Self.movieBytes())])
        lab.select(path: "interface\\absent.swf")
        #expect(lab.snapshot.loadError != nil)
    }

    /// Without a renderer the toggle reads the default, on, and ignores a set.
    @Test @MainActor
    func layerToggleIsInertWithoutARenderer() {
        let lab = Self.makeLab()
        #expect(lab.layerEnabled)
        lab.layerEnabled = false
        #expect(lab.layerEnabled)
    }

    /// Every runtime action reports why it did nothing instead of throwing.
    @Test @MainActor
    func runtimeControlsReportInsteadOfThrowingWithoutARenderer() {
        let lab = Self.makeLab()
        lab.startRuntime()
        #expect(lab.snapshot.loadError?.contains("No renderer") == true)
        #expect(lab.snapshot.runtime == nil)

        for action in [
            { lab.advanceRuntime(ticks: 20) },
            { lab.sendRuntimeInput(.keyDown(code: SWFKeyCode.right, ascii: 0)) },
            { lab.callRuntimeMovie("StartOpenMenuAnim") },
            { lab.stopRuntime() },
            { lab.clearInvokeLog() }
        ] {
            action()
        }
        #expect(lab.snapshot.loadError != nil)
    }

    /// An empty callback name is a user mistake, not a bridge call.
    @Test @MainActor
    func blankCallbackNameIsRejectedBeforeTheBridge() {
        let lab = Self.makeLab()
        lab.callRuntimeMovie("   ")
        #expect(lab.snapshot.loadError == "Enter a callback name to call.")
    }

    /// The runtime half stays nil while the layer is on the static frame-1 path.
    @Test @MainActor
    func snapshotCarriesNoRuntimeOnTheStaticPath() throws {
        let lab = try makeController(movies: [("alpha.swf", Self.movieBytes())])
        lab.select(path: "interface\\alpha.swf")
        let snapshot = lab.snapshot
        #expect(snapshot.runtime == nil)
        #expect(SWFLabReadout.runtimeText(for: snapshot).hasPrefix("Runtime: stopped"))
        #expect(SWFLabReadout.invokeText(for: snapshot) == "Invokes: runtime not started")
        #expect(SWFLabReadout.tallyText(for: snapshot) == "Ops: runtime not started")
    }

    /// With a renderer the lab runs the movie, and clearing the selection hands
    /// the layer back to the HUD, which fails here: the archive has no HUD movie.
    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device)) @MainActor
    func runtimeRunsOnARendererAndClearingRestartsTheHUD() throws {
        let movies = try SWFMovieSource(
            fileSystem: makeFiles(movies: [("alpha.swf", Self.movieBytes())]),
            loadsImmediately: true
        )
        let hud = HUDCoordinator(movies: movies)
        let lab = SWFLabCoordinator(movies: movies, hud: hud)
        let canvas = OffscreenCanvas(width: 64, height: 64, shaders: .packageFixture)
        let world = try FakeSWFLayerWorld(renderer: canvas.makeRenderer())
        hud.attach(world: world)
        lab.attach(world: world)

        lab.select(path: "interface\\alpha.swf")
        lab.startRuntime()
        lab.advanceRuntime(ticks: 3)
        #expect(lab.loadError == nil)
        #expect(lab.snapshot.runtime?.isStarted == true)

        lab.select(path: nil)
        #expect(!hud.isLoaded)
        #expect(hud.loadError != nil)
    }
}
