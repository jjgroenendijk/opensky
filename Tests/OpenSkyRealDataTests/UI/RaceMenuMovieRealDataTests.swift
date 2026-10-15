// The race menu movie on the user's install: one key press moves the race list one
// row, and the cursor reaches the category arrows and the Done button.

import Foundation
@testable import OpenSkyFormatsSWF
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import Testing

struct RaceMenuMovieRealDataTests {
    @MainActor
    private final class Requests {
        var seen: [RaceMenuMovieBridge.Request] = []
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot)) @MainActor
    func oneKeyPressMovesTheRaceListOneRow() throws {
        let (runtime, _) = try startMovie()
        let before = try #require(selectedRace(runtime))
        RaceMenuMovieBridge.handle(.move(.down), runtime: runtime)
        advance(runtime)
        #expect(selectedRace(runtime) == before + 1)
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot)) @MainActor
    func theCursorReachesTheCategoryArrowAndDone() throws {
        let (runtime, requests) = try startMovie()
        let base = try #require(panels(runtime)?.parent)
        let category = categoryIndex(runtime)
        let right = try #require(child("RightClickInstance", of: base))
        click(center(of: right, runtime), runtime: runtime)
        #expect(categoryIndex(runtime) != category, "a click on the right arrow kept the category")
        let done = try #require(panels(runtime)?.object.lookup("DoneButton")?.property.value
            .objectValue)
        try click(center(of: #require(SWFDisplayObject.resolve(done)), runtime), runtime: runtime)
        #expect(requests.seen.contains(.done), "a click on Done sent no ConfirmDone")
    }

    @MainActor
    private func child(_ name: String, of node: SWFDisplayObject) -> SWFDisplayObject? {
        node.object.lookup(name)?.property.value.objectValue
            .flatMap { SWFDisplayObject.resolve($0) }
    }

    /// The node's centre in stage pixels.
    @MainActor
    private func center(of node: SWFDisplayObject, _ runtime: SWFMovieRuntime) -> SIMD2<Float> {
        let box = runtime.localBounds(of: node)
        let local = SIMD2((box.minX + box.maxX) / 2, (box.minY + box.maxY) / 2)
        return (runtime.transform(of: node) ?? .identity).apply(local) / SWFMovieRuntime
            .twipsPerPixel
    }

    @MainActor
    private func click(_ point: SIMD2<Float>, runtime: SWFMovieRuntime) {
        let frame = runtime.movie.frameSize
        let size = SIMD2(Float(frame.xMax - frame.xMin), Float(frame.yMax - frame.yMin)) / 20
        for phase in [MenuPointerEvent.Phase.moved, .pressed, .released] {
            TitleMenuMovieBridge.handle(
                MenuPointerEvent(phase, location: point, viewSize: size), runtime: runtime
            )
        }
        runtime.advance()
    }

    @MainActor
    private func panels(_ runtime: SWFMovieRuntime) -> SWFDisplayObject? {
        runtime.node(atPath: RaceMenuMovieBridge.panelsPath, from: runtime.root)
    }

    @MainActor
    private func listIndex(_ name: String, _ runtime: SWFMovieRuntime) -> Int? {
        guard
            let list = panels(runtime)?.object.lookup(name)?.property.value.objectValue,
            case let .number(index) = runtime.resolve("selectedIndex", on: list)
        else { return nil }
        return Int(index)
    }

    @MainActor
    private func selectedRace(_ runtime: SWFMovieRuntime) -> Int? {
        listIndex("_SubList1", runtime)
    }

    @MainActor
    private func categoryIndex(_ runtime: SWFMovieRuntime) -> Int? {
        listIndex("_CategoriesList", runtime)
    }

    @MainActor
    private func startMovie() throws -> (SWFMovieRuntime, Requests) {
        let root = try #require(RealDataEnvironment.dataRoot)
        let loader = SWFMovieLoader(fileSystem: VirtualFileSystem(root: root))
        let runtime = try SWFMovieRuntime(movieScene: loader
            .load(path: RaceMenuMovieBridge.moviePath))
        let requests = Requests()
        RaceMenuMovieBridge.prepare(runtime: runtime) { requests.seen.append($0) }
        runtime.start()
        advance(runtime)
        RaceMenuMovieBridge.setPlatform(runtime: runtime)
        let categories: [AS2Value] = ["Race", "Body", "Head"].enumerated().flatMap {
            [AS2Value.string($0.element), .integer(1 << $0.offset)]
        }
        runtime.callMovie("SetCategoriesList", arguments: categories)
        let races: [AS2Value] = ["Nord", "Orc", "Redguard", "Breton"].enumerated().flatMap {
            [AS2Value.string($0.element), .string("text"), .integer($0.offset == 0 ? 1 : 0)]
        }
        runtime.callMovie("SetRaceList", arguments: races)
        runtime.callMovie("SetOptionSliders", arguments: [
            .string("Weight"), .integer(2), .string("ChangeWeight"), .number(0), .number(100),
            .number(50), .number(1), .integer(0)
        ])
        advance(runtime)
        return (runtime, requests)
    }

    @MainActor
    private func advance(_ runtime: SWFMovieRuntime) {
        for _ in 0 ..< 10 {
            runtime.advance()
        }
    }
}
