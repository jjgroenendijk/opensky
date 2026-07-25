// Array behavior, enumeration order, and property-flag editing for
// `AS2Object` (milestone 8.3.2). Split from `AS2Object.swift` to keep both
// files inside the strict-lint size caps.
//
// Reference: ECMA-262 3rd edition, section 15.4 "Array Objects" for the
// `length` rules (15.4.5.1 "[[Put]] (P, V)") and section 12.6.4 "The for-in
// Statement" for the enumeration set that `ActionEnumerate2` (0x55) produces.

import Foundation

extension AS2Object {
    /// Reads an array element by index. Elements live in the ordinary property
    /// table under their decimal names, as ECMAScript specifies.
    func element(at index: Int) -> AS2Value {
        ownProperty(String(index))?.value ?? .undefined
    }

    /// Writes an array element and extends `length` when the index is past the
    /// end.
    func setElement(_ value: AS2Value, at index: Int) {
        guard index >= 0 else {
            return
        }
        define(value, for: String(index))
        if let length = arrayLength, index >= length {
            markArray(length: index + 1)
        }
    }

    /// Appends to an array-like object.
    func appendElement(_ value: AS2Value) {
        setElement(value, at: arrayLength ?? 0)
    }

    /// Every element in index order, `undefined` for holes.
    var elements: [AS2Value] {
        guard let length = arrayLength else {
            return []
        }
        return (0 ..< length).map { element(at: $0) }
    }

    /// Applies an array `length` assignment: shrinking drops the elements past
    /// the new end, growing only moves the mark.
    func resizeArray(to length: Int) {
        let clamped = max(0, length)
        if let current = arrayLength, clamped < current {
            for index in clamped ..< current {
                removeProperty(String(index))
            }
        }
        markArray(length: clamped)
    }
}

extension AS2Object {
    /// The names `ActionEnumerate2` yields: own properties first, then each
    /// prototype's, skipping `dontEnumerate` slots and names already seen.
    /// Insertion order is used throughout, which the specification leaves
    /// implementation-defined; picking a fixed order keeps a menu's iteration
    /// deterministic across runs.
    func enumerableNames() -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        var current: AS2Object? = self
        var steps = 0
        while let object = current, steps < AS2Object.prototypeChainLimit {
            for name in object.ownPropertyNames {
                guard
                    let property = object.ownProperty(name),
                    !property.flags.contains(.dontEnumerate),
                    seen.insert(name).inserted
                else {
                    continue
                }
                names.append(name)
            }
            current = object.prototype
            steps += 1
        }
        return names
    }

    /// `ASSetPropFlags(object, names, setFlags, clearFlags)`. A nil name list
    /// means every own property. Clearing wins over setting for a bit named in
    /// both, matching the built-in's documented order of operations.
    func applyPropertyFlags(
        names: [String]?,
        adding: AS2PropertyFlags,
        removing: AS2PropertyFlags
    ) {
        for name in names ?? ownPropertyNames {
            guard let property = ownProperty(name) else {
                continue
            }
            var flags = property.flags
            flags.formUnion(adding)
            flags.subtract(removing)
            setFlags(flags, for: name)
        }
    }
}
