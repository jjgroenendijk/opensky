// Engine pictures in a movie: an image slot adds a bitmap and a shape that draws
// it, and `MovieClipLoader.loadClip("img://...")` shows that shape.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsSWF
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFImageSlotTests {
    private static func scene() throws -> SWFMovieScene {
        let movie = try SWFDisplayFixture.movie(tags: [SWFDisplayFixture.showFrameTag])
        return SWFMovieScene(movie: movie).addingImageSlot("Shot", width: 4, height: 2)
    }

    @Test func aSlotAddsABitmapAndAShapeThatFillsWithIt() throws {
        let scene = try Self.scene()
        let slot = try #require(scene.movie.imageSlots["Shot"])
        guard
            case let .bitmap(bitmap)? = scene.movie.characters[slot.bitmapId],
            case let .shape(shape)? = scene.movie.characters[slot.shapeId]
        else {
            Issue.record("the slot characters are missing")
            return
        }
        #expect(bitmap.width == 4 && bitmap.height == 2 && bitmap.pixels.count == 32)
        #expect(shape.bounds == SWFRect(xMin: 0, xMax: 80, yMin: 0, yMax: 40))
        #expect(SWFShapeTessellator.tessellate(shape).runs.count == 1)
        let again = scene.addingImageSlot("Shot", width: 8, height: 8)
        #expect(again.movie.imageSlots["Shot"] == slot)
    }

    @Test func loadClipShowsThePictureAndReportsInit() throws {
        let runtime = try SWFMovieRuntime(movieScene: Self.scene())
        runtime.start()
        let target = SWFDisplayObject(content: .clip(nil))
        runtime.root.addChild(target, atDepth: 1)
        let loader = try Self.loader(runtime)
        var initialized = 0
        let listener = runtime.runtime.makeObject()
        AS2Natives.method(runtime.runtime, on: listener, name: "onLoadInit") { _ in
            initialized += 1
            return .undefined
        }
        Self.call("addListener", on: loader, [.object(listener)], runtime)
        let started = Self.call(
            "loadClip",
            on: loader,
            [.string("img://Shot"), .object(target.object)],
            runtime
        )
        #expect(started == .boolean(true))
        #expect(target.children.count == 1)
        runtime.advance()
        runtime.advance()
        #expect(initialized == 1)
        let missing = Self.call(
            "loadClip",
            on: loader,
            [.string("img://Other"), .object(target.object)],
            runtime
        )
        #expect(missing == .boolean(false))
    }

    private static func loader(_ runtime: SWFMovieRuntime) throws -> AS2Object {
        let constructor = try #require(runtime.runtime.globalValue("MovieClipLoader").objectValue)
        let prototype = constructor.lookup("prototype")?.property.value.objectValue
        let loader = AS2Object(prototype: prototype ?? runtime.runtime.objectPrototype)
        runtime.runtime.invoke(.object(constructor), thisValue: .object(loader))
        return loader
    }

    @discardableResult
    private static func call(
        _ name: String, on object: AS2Object, _ arguments: [AS2Value], _ runtime: SWFMovieRuntime
    ) -> AS2Value {
        let function = object.lookup(name)?.property.value ?? .undefined
        return runtime.runtime.invoke(function, thisValue: .object(object), arguments: arguments)
            .value
    }
}
