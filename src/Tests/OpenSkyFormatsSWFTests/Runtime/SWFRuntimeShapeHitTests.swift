// The pointer and `hitTest(x, y, true)` reach a clip only where its shapes draw. An
// L-shaped clip of two bars has a bounding box with an empty corner.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct SWFRuntimeShapeHitTests {
    /// Sprite `corner` holds a 2000x400 bar and a 400x1200 bar, both from (0, 0): its box
    /// is 2000x1200 twips, and (1600, 1000) lies in the box but on neither bar.
    private static func started() throws -> (SWFMovieRuntime, SWFDisplayObject) {
        let runtime = try SWFRuntimeFixture.started(tags: [
            SWFRuntimeFixture.rectangle(id: 2, width: 2000, height: 400),
            SWFRuntimeFixture.rectangle(id: 3, width: 400, height: 1200),
            SWFDisplayFixture.spriteTag(characterId: 4, frameCount: 1, tags: [
                SWFRuntimeFixture.place(2, depth: 1),
                SWFRuntimeFixture.place(3, depth: 2),
                SWFDisplayFixture.showFrameTag
            ]),
            SWFRuntimeFixture.place(4, depth: 1, name: "corner"),
            SWFDisplayFixture.showFrameTag
        ])
        return try (runtime, #require(runtime.root.child(named: "corner")))
    }

    private func call(
        _ runtime: SWFMovieRuntime,
        on node: SWFDisplayObject,
        _ arguments: [AS2Value]
    ) throws -> AS2Value {
        let member = node.object.lookup("hitTest")?.property.value
            ?? runtime.member("hitTest", of: node)
        let function = try #require(member?.functionValue)
        return AS2Interpreter.invoke(
            in: runtime.runtime,
            .object(function),
            thisValue: .object(node.object),
            arguments: arguments
        ).value
    }

    @Test func thePointerReachesTheClipOnlyOnItsShapes() throws {
        let (runtime, corner) = try Self.started()
        AS2Runtime.method(runtime.runtime, on: corner.object, name: "onPress") { _ in .undefined }
        #expect(runtime.hitTest(stageTwips: SIMD2(1600, 200)).target === corner)
        #expect(runtime.hitTest(stageTwips: SIMD2(200, 1000)).target === corner)
        let miss = runtime.hitTest(stageTwips: SIMD2(1600, 1000))
        #expect(miss.target == nil)
        #expect(miss.topmost == nil)
    }

    @Test func aTransparentHitAreaCatchesThePointerOnlyOnItsShapes() throws {
        let (runtime, corner) = try Self.started()
        AS2Runtime.method(runtime.runtime, on: corner.object, name: "onPress") { _ in .undefined }
        corner.alpha = 0
        #expect(runtime.hitTest(stageTwips: SIMD2(200, 1000)).target === corner)
        #expect(runtime.hitTest(stageTwips: SIMD2(1600, 1000)).target == nil)
    }

    @Test func hitTestWithTheShapeFlagTestsTheShapes() throws {
        let (runtime, corner) = try Self.started()
        // (1600, 1000) twips is (80, 50) pixels.
        #expect(try call(runtime, on: corner, [.number(80), .number(50)]) == .boolean(true))
        #expect(
            try call(runtime, on: corner, [.number(80), .number(50), .boolean(true)])
                == .boolean(false)
        )
        #expect(
            try call(runtime, on: corner, [.number(80), .number(10), .boolean(true)])
                == .boolean(true)
        )
    }

    @Test func aMeshContainsPointsInItsTrianglesOnly() {
        let mesh = SWFShapeMesh(
            vertices: [
                SIMD2(0, 0),
                SIMD2(100, 0),
                SIMD2(0, 100),
                SIMD2(5, 5),
                SIMD2(5, 5),
                SIMD2(5, 5)
            ],
            runs: []
        )
        #expect(mesh.contains(SIMD2(10, 10)))
        #expect(mesh.contains(SIMD2(50, 50)))
        #expect(!mesh.contains(SIMD2(60, 60)))
        // The second triangle has no area, so its point is not a hit by itself.
        let flat = SWFShapeMesh(vertices: [SIMD2(5, 5), SIMD2(5, 5), SIMD2(5, 5)], runs: [])
        #expect(!flat.contains(SIMD2(5, 5)))
    }
}
