// `Array.splice`, `reverse`, `sort`, and `sortOn`. The race menu clears each list
// with `splice(0, length)` before it fills the list again.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct AS2ArrayOrderTests {
    private let runtime = AS2Runtime()

    private func call(_ name: String, on array: AS2Object, _ arguments: [AS2Value]) -> AS2Value {
        let method = runtime.arrayPrototype.lookup(name)?.property.value ?? .undefined
        return runtime.invoke(method, thisValue: .object(array), arguments: arguments).value
    }

    private func array(_ values: [AS2Value]) -> AS2Object {
        runtime.makeArray(values)
    }

    @Test func spliceRemovesInsertsAndReturnsTheRemoved() {
        let list = array([.integer(1), .integer(2), .integer(3), .integer(4)])
        let removed = call("splice", on: list, [.integer(1), .integer(2), .string("x")])
        #expect(removed.objectValue?.elements == [.integer(2), .integer(3)])
        #expect(list.elements == [.integer(1), .string("x"), .integer(4)])
        _ = call("splice", on: list, [.integer(0), .integer(list.arrayLength ?? 0)])
        #expect(list.elements.isEmpty, "splice(0, length) clears the list")
        let tail = array([.integer(1), .integer(2), .integer(3)])
        _ = call("splice", on: tail, [.integer(-1)])
        #expect(tail.elements == [.integer(1), .integer(2)], "no count cuts to the end")
        _ = call("splice", on: tail, [.integer(0), .number(1e300)])
        #expect(tail.elements.isEmpty, "a huge count is clamped")
    }

    @Test func reverseWorksInPlace() {
        let list = array([.integer(1), .integer(2), .integer(3)])
        #expect(call("reverse", on: list, []) == .object(list))
        #expect(list.elements == [.integer(3), .integer(2), .integer(1)])
    }

    @Test func sortComparesTextUnlessToldNumeric() {
        let list = array([.integer(10), .integer(9), .undefined, .integer(100)])
        _ = call("sort", on: list, [])
        #expect(list.elements == [.integer(10), .integer(100), .integer(9), .undefined])
        _ = call("sort", on: list, [.integer(16 | 2)])
        #expect(list.elements == [.integer(100), .integer(10), .integer(9), .undefined])
        let words = array([.string("b"), .string("A"), .string("a")])
        #expect(call("sort", on: words, [.integer(4 | 1)]) == .integer(0), "a tie fails UNIQUESORT")
        #expect(words.elements == [.string("b"), .string("A"), .string("a")])
        let indices = call("sort", on: words, [.integer(8)])
        #expect(indices.objectValue?.elements == [.integer(1), .integer(2), .integer(0)])
    }

    @Test func sortOnOrdersObjectsByAField() {
        func row(_ text: String, _ count: Int) -> AS2Value {
            let object = runtime.makeObject()
            object.assign(.string(text), for: "text")
            object.assign(.integer(count), for: "count")
            return .object(object)
        }
        let rows = [row("Iron", 3), row("Gold", 1), row("Ebony", 2)]
        let list = array(rows)
        _ = call("sortOn", on: list, [.string("count"), .integer(16)])
        #expect(list.elements == [rows[1], rows[2], rows[0]])
        _ = call("sortOn", on: list, [.string("text")])
        #expect(list.elements == [rows[2], rows[1], rows[0]])
    }

    @Test func theSortFlagsAreOnTheConstructor() {
        let constructor = runtime.globalValue("Array").objectValue
        #expect(constructor?.lookup("NUMERIC")?.property.value == .integer(16))
        #expect(constructor?.lookup("RETURNINDEXEDARRAY")?.property.value == .integer(8))
    }
}
