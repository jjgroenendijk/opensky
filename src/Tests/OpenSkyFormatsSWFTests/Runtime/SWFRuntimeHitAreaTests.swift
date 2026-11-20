// Alpha 0 and the pointer: an alpha-0 clip with its own handler is a hit area, and
// nothing inside an alpha-0 subtree catches the pointer.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct SWFRuntimeHitAreaTests {
    /// A sprite named `page` at (400, 300) twips holds a sprite named `button` with a
    /// 2000x1200 twip rectangle.
    private struct Scene {
        let runtime: SWFMovieRuntime
        let page: SWFDisplayObject
        let button: SWFDisplayObject
    }

    private static func started() throws -> Scene {
        var inner = SWFDisplayFixture.Place2()
        inner.depth = 1
        inner.characterId = 3
        inner.name = "button"
        var page = SWFDisplayFixture.Place2()
        page.depth = 4
        page.characterId = 4
        page.name = "page"
        page.matrix = SWFDisplayFixture.MatrixSpec(translateX: 400, translateY: 300)
        let runtime = try SWFRuntimeFixture.started(tags: [
            SWFRuntimeFixture.rectangle(id: 2, width: 2000, height: 1200),
            SWFDisplayFixture.spriteTag(characterId: 3, frameCount: 1, tags: [
                SWFRuntimeFixture.place(2, depth: 1), SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.spriteTag(characterId: 4, frameCount: 1, tags: [
                SWFDisplayFixture.placeObject2Tag(inner), SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.placeObject2Tag(page), SWFDisplayFixture.showFrameTag
        ])
        let pageNode = try #require(runtime.root.child(named: "page"))
        let button = try #require(pageNode.child(named: "button"))
        return Scene(runtime: runtime, page: pageNode, button: button)
    }

    private static func handle(
        _ name: String,
        on node: SWFDisplayObject,
        in runtime: SWFMovieRuntime
    ) {
        AS2Runtime.method(runtime.runtime, on: node.object, name: name) { _ in .undefined }
    }

    @Test func aTransparentClipCatchesThePointerOnlyWithAHandler() throws {
        let scene = try Self.started()
        let (runtime, button) = (scene.runtime, scene.button)
        button.alpha = 0
        #expect(runtime.hitTest(stageTwips: SIMD2(1000, 800)).topmost == nil)
        Self.handle("onMouseDown", on: button, in: runtime)
        let hit = runtime.hitTest(stageTwips: SIMD2(1000, 800))
        #expect(hit.target === button)
        #expect(hit.topmost === button)
        runtime.handle(.pointerMoved(x: 50, y: 40))
        #expect(runtime.topMostEntity() === button)
    }

    @Test func aTransparentParentHidesTheClipsInsideIt() throws {
        let scene = try Self.started()
        let runtime = scene.runtime
        let button = scene.button
        Self.handle("onPress", on: button, in: runtime)
        #expect(runtime.hitTest(stageTwips: SIMD2(1000, 800)).target === button)
        scene.page.alpha = 0
        #expect(runtime.hitTest(stageTwips: SIMD2(1000, 800)).target == nil)
    }
}
