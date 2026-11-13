// `flash.geom.Rectangle` and `Point`: the constructor's fields and the methods that read
// and change them, as the Adobe ActionScript 2.0 reference describes them.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFGeometryTests {
    private static func started() throws -> SWFMovieRuntime {
        let movie = try SWFDisplayFixture.movie(tags: [SWFDisplayFixture.showFrameTag])
        let runtime = SWFMovieRuntime(movieScene: SWFMovieScene(movie: movie))
        runtime.start()
        return runtime
    }

    private static func rectangle(
        _ values: [Double], in runtime: SWFMovieRuntime, className: String = "Rectangle"
    ) throws -> AS2Object {
        let flash = try #require(runtime.runtime.globalValue("flash").objectValue)
        let geometry = try #require(flash.lookup("geom")?.property.value.objectValue)
        let constructor = try #require(geometry.lookup(className)?.property.value.objectValue)
        let prototype = constructor.lookup("prototype")?.property.value.objectValue
        let instance = AS2Object(prototype: prototype ?? runtime.runtime.objectPrototype)
        AS2Interpreter.invoke(
            in: runtime.runtime, .object(constructor), thisValue: .object(instance),
            arguments: values.map(AS2Value.number)
        )
        return instance
    }

    @discardableResult
    private static func call(
        _ name: String, on object: AS2Object, _ arguments: [AS2Value], _ runtime: SWFMovieRuntime
    ) -> AS2Value {
        AS2Interpreter.invoke(
            in: runtime.runtime,
            object.lookup(name)?.property.value ?? .undefined,
            thisValue: .object(object),
            arguments: arguments
        )
        .value
    }

    private static func fields(_ object: AS2Object) -> [Double] {
        ["x", "y", "width", "height"].map {
            AS2Fixture.number(object.lookup($0)?.property.value ?? .undefined)
        }
    }

    @Test func theConstructorSetsTheFourFields() throws {
        let runtime = try Self.started()
        let box = try Self.rectangle([1, 2, 3, 4], in: runtime)
        #expect(Self.fields(box) == [1, 2, 3, 4])
        let text = Self.call("toString", on: box, [], runtime)
        #expect(text == .string("(x=1, y=2, w=3, h=4)"))
    }

    /// The right and bottom edges are outside, as in Flash.
    @Test func containsTakesTheTopLeftEdgeOnly() throws {
        let runtime = try Self.started()
        let box = try Self.rectangle([0, 0, 10, 10], in: runtime)
        #expect(Self.call("contains", on: box, [.number(0), .number(0)], runtime) == .boolean(true))
        #expect(Self
            .call("contains", on: box, [.number(10), .number(5)], runtime) == .boolean(false))
        #expect(Self.call("isEmpty", on: box, [], runtime) == .boolean(false))
    }

    @Test func intersectionAndUnionBuildNewRectangles() throws {
        let runtime = try Self.started()
        let lhs = try Self.rectangle([0, 0, 10, 10], in: runtime)
        let rhs = try Self.rectangle([5, 5, 10, 10], in: runtime)
        let shared = try #require(Self.call("intersection", on: lhs, [.object(rhs)], runtime)
            .objectValue)
        #expect(Self.fields(shared) == [5, 5, 5, 5])
        let both = try #require(Self.call("union", on: lhs, [.object(rhs)], runtime).objectValue)
        #expect(Self.fields(both) == [0, 0, 15, 15])
        let apart = try Self.rectangle([20, 20, 1, 1], in: runtime)
        #expect(Self.call("intersects", on: lhs, [.object(apart)], runtime) == .boolean(false))
    }

    @Test func offsetInflateAndSetEmptyChangeTheRectangleInPlace() throws {
        let runtime = try Self.started()
        let box = try Self.rectangle([1, 1, 2, 2], in: runtime)
        Self.call("offset", on: box, [.number(1), .number(2)], runtime)
        #expect(Self.fields(box) == [2, 3, 2, 2])
        Self.call("inflate", on: box, [.number(1), .number(1)], runtime)
        #expect(Self.fields(box) == [1, 2, 4, 4])
        Self.call("setEmpty", on: box, [], runtime)
        #expect(Self.call("isEmpty", on: box, [], runtime) == .boolean(true))
    }

    /// Flash prints whole numbers without a fraction.
    @Test func aPointPrintsItsCoordinatesAsFlashDoes() throws {
        let runtime = try Self.started()
        let point = try Self.rectangle([1, 2.5], in: runtime, className: "Point")
        #expect(Self.call("toString", on: point, [], runtime) == .string("(x=1, y=2.5)"))
    }
}
