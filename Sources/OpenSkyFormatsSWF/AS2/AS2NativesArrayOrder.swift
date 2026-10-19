// The `Array` methods that reorder or cut an array: `splice`, `reverse`, `sort`,
// and `sortOn`, with the sort option flags on the constructor.
//
// Reference: ECMA-262 3rd edition, section 15.4.4 (15.4.4.8 `reverse`, 15.4.4.11
// `sort`, 15.4.4.12 `splice`). `sortOn` and the option flags are Flash additions,
// from the ActionScript 2.0 Language Reference, "Array class".

import Foundation

nonisolated extension AS2Natives {
    /// The sort option bits of `Array.CASEINSENSITIVE` and its siblings.
    struct ArraySortOptions: OptionSet {
        let rawValue: Int
        static let caseInsensitive = Self(rawValue: 1)
        static let descending = Self(rawValue: 2)
        static let uniqueSort = Self(rawValue: 4)
        static let returnIndexedArray = Self(rawValue: 8)
        static let numeric = Self(rawValue: 16)
    }

    static let arraySortConstants: [(String, Int)] = [
        ("CASEINSENSITIVE", 1), ("DESCENDING", 2), ("UNIQUESORT", 4),
        ("RETURNINDEXEDARRAY", 8), ("NUMERIC", 16)
    ]

    static func installArrayOrder(_ runtime: AS2Runtime, on prototype: AS2Object) {
        method(runtime, on: prototype, name: "splice") { context in
            guard let array = context.thisObject else {
                return .undefined
            }
            var elements = array.elements
            let start = try bound(context.number(0), count: elements.count, fallback: 0)
            var removeCount = elements.count - start
            if context.arguments.count > 1 {
                let asked = try context.number(1)
                removeCount = asked.isFinite ? min(Int(min(max(asked, 0), 1e9)), removeCount) : 0
            }
            let removed = Array(elements[start ..< start + removeCount])
            elements.replaceSubrange(
                start ..< start + removeCount, with: context.arguments.dropFirst(2)
            )
            replace(array, with: elements)
            return .object(context.runtime.makeArray(removed))
        }
        method(runtime, on: prototype, name: "reverse") { context in
            guard let array = context.thisObject else {
                return .undefined
            }
            replace(array, with: array.elements.reversed())
            return .object(array)
        }
        method(runtime, on: prototype, name: "sort") { context in
            guard let array = context.thisObject else {
                return .undefined
            }
            let compare = context.argument(0).functionValue
            let flags = try context.number(compare == nil ? 0 : 1)
            let options = ArraySortOptions(rawValue: flags.isFinite ? Int(flags) & 31 : 0)
            return try sorted(array, options: options, context: context) { left, right in
                if let compare {
                    let order = try context.interpreter.toNumber(context.interpreter.call(
                        compare, thisValue: .undefined, arguments: [left, right], offset: 0
                    ))
                    return options.contains(.descending) ? -order : order
                }
                return try compareValues(left, right, options: options, context: context)
            }
        }
        installSortOn(runtime, on: prototype)
    }

    private static func installSortOn(_ runtime: AS2Runtime, on prototype: AS2Object) {
        method(runtime, on: prototype, name: "sortOn") { context in
            guard let array = context.thisObject else {
                return .undefined
            }
            let fields = context.argument(0).objectValue?.elements ?? [context.argument(0)]
            let names = try fields.map { try context.interpreter.toString($0) }
            let flags = try context.number(1)
            let options = ArraySortOptions(rawValue: flags.isFinite ? Int(flags) & 31 : 0)
            return try sorted(array, options: options, context: context) { left, right in
                for name in names {
                    let order = try compareValues(
                        context.interpreter.getMember(name, of: left, offset: 0),
                        context.interpreter.getMember(name, of: right, offset: 0),
                        options: options, context: context
                    )
                    if order != 0 {
                        return order
                    }
                }
                return 0
            }
        }
    }

    /// Sorts in place, or returns the sorted indices for `RETURNINDEXEDARRAY`.
    /// `UNIQUESORT` leaves the array as it was and returns 0 when two elements tie.
    private static func sorted(
        _ array: AS2Object, options: ArraySortOptions, context: AS2CallContext,
        compare: (AS2Value, AS2Value) throws -> Double
    ) throws -> AS2Value {
        let elements = array.elements
        var tie = false
        let order = try elements.indices.sorted { left, right in
            let result = try compare(elements[left], elements[right])
            tie = tie || result == 0
            return result < 0
        }
        if options.contains(.uniqueSort), tie {
            return .integer(0)
        }
        if options.contains(.returnIndexedArray) {
            return .object(context.runtime.makeArray(order.map { .integer($0) }))
        }
        replace(array, with: order.map { elements[$0] })
        return .object(array)
    }

    /// The default order compares text, `NUMERIC` compares numbers, and `undefined`
    /// goes last in either direction.
    private static func compareValues(
        _ left: AS2Value, _ right: AS2Value, options: ArraySortOptions, context: AS2CallContext
    ) throws -> Double {
        switch (left, right) {
        case (.undefined, .undefined): return 0
        case (.undefined, _): return 1
        case (_, .undefined): return -1
        default:
            let order = try compareDefined(left, right, options: options, context: context)
            return options.contains(.descending) ? -order : order
        }
    }

    private static func compareDefined(
        _ left: AS2Value, _ right: AS2Value, options: ArraySortOptions, context: AS2CallContext
    ) throws -> Double {
        if options.contains(.numeric) {
            let lhs = try context.interpreter.toNumber(left)
            let rhs = try context.interpreter.toNumber(right)
            return lhs < rhs ? -1 : (lhs > rhs ? 1 : 0)
        }
        var lhs = try context.interpreter.toString(left)
        var rhs = try context.interpreter.toString(right)
        if options.contains(.caseInsensitive) {
            (lhs, rhs) = (lhs.lowercased(), rhs.lowercased())
        }
        if lhs == rhs {
            return 0
        }
        return lhs.utf16.lexicographicallyPrecedes(rhs.utf16) ? -1 : 1
    }
}
