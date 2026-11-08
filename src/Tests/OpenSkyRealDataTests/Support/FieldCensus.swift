// Counts, per decoded field, how many records of the install set it. A field
// that no record sets points at a decoder that never reaches it.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM

struct FieldCensus {
    typealias Probe<Root> = (name: String, read: (Root) -> Any?)

    /// "Owner.field" to the number of values that set it.
    private(set) var setCounts: [String: Int] = [:]
    /// "Type.field" to the number of values that set it, over every owner.
    private(set) var typeSetCounts: [String: Int] = [:]
    private(set) var ownerCounts: [String: Int] = [:]
    /// Owner to the fields its decoder left unread.
    private(set) var unread: [String: Int] = [:]

    mutating func count<Root>(
        _ owner: String,
        _ roots: some Sequence<Root>,
        _ probes: [Probe<Root>]
    ) {
        for root in roots {
            ownerCounts[owner, default: 0] += 1
            for probe in probes {
                let set = Self.isSet(probe.read(root)) ? 1 : 0
                setCounts["\(owner).\(probe.name)", default: 0] += set
                typeSetCounts["\(Root.self).\(probe.name)", default: 0] += set
            }
        }
    }

    mutating func count<Root>(_ owner: String, _ root: Root?, _ probes: [Probe<Root>]) {
        count(owner, root.map { [$0] } ?? [], probes)
    }

    mutating func tally(_ owner: String, _ skipped: FieldTally) {
        unread[owner, default: 0] += skipped.total
    }

    /// Fields of a decoded type that no record of any owner sets.
    var neverSet: [String] {
        typeSetCounts.filter { $0.value == 0 }.keys.sorted()
    }

    var report: [String] {
        var lines = ownerCounts.keys.sorted().map { "[INFO] \($0) \(ownerCounts[$0] ?? 0)" }
        lines += setCounts.keys.sorted().map { "  \($0): \(setCounts[$0] ?? 0)" }
        lines += unread.keys.sorted().map { "  unread \($0): \(unread[$0] ?? 0)" }
        return lines
    }

    /// False for nil, false, zero, a null form ID, and an empty value.
    static func isSet(_ value: Any?) -> Bool {
        guard let value else { return false }
        if let optional = value as? any OptionalValue {
            return optional.wrapped.map(isSet) ?? false
        }
        switch value {
        case let flag as Bool: return flag
        case let formID as FormID: return !formID.isNull
        case let integer as any BinaryInteger: return isNonZero(integer)
        case let real as any BinaryFloatingPoint: return !real.isZero
        case let vector as any SIMD: return isNonZero(vector)
        case let collection as any Collection: return !collection.isEmpty
        default: return true
        }
    }

    private static func isNonZero(_ integer: some BinaryInteger) -> Bool {
        integer != 0
    }

    private static func isNonZero<Vector: SIMD>(_ vector: Vector) -> Bool {
        vector != Vector()
    }
}

private protocol OptionalValue {
    var wrapped: Any? { get }
}

extension Optional: OptionalValue {
    fileprivate var wrapped: Any? {
        map(\.self)
    }
}
