// The save's three-byte form reference: two kind bits and a 22-bit value, stored big
// endian. See docs/formats/ess.md#ref-ids.

import Foundation

nonisolated public struct ESSRefID: Hashable, Sendable {
    nonisolated public enum Kind: UInt8, CaseIterable, Sendable {
        /// The value is one past an index into the form id array; 0 is the null form.
        case formIDArray = 0
        /// A form of the first master, `Skyrim.esm`, by its object id.
        case `default` = 1
        /// A form the game created at runtime, the `0xFF` plugin index.
        case created = 2
        /// Undocumented. Counted, never resolved.
        case unknown = 3

        public var name: String {
            switch self {
            case .formIDArray: "form id array"
            case .default: "first master"
            case .created: "created"
            case .unknown: "unknown"
            }
        }
    }

    /// The 24 stored bits, kind bits included.
    public let raw: UInt32

    public init(raw: UInt32) {
        self.raw = raw & 0x00FF_FFFF
    }

    public init(kind: Kind, value: UInt32) {
        self.init(raw: UInt32(kind.rawValue) << 22 | (value & 0x003F_FFFF))
    }

    public var kind: Kind {
        Kind(rawValue: UInt8(raw >> 22)) ?? .unknown
    }

    public var value: UInt32 {
        raw & 0x003F_FFFF
    }

    public var isNull: Bool {
        raw == 0
    }

    /// The runtime form id this names, in the save's own load order. Nil for the null
    /// form, an index past the array, and the unknown kind.
    public func formID(in formIDArray: [UInt32]) -> UInt32? {
        switch kind {
        case .formIDArray:
            guard value > 0, Int(value) <= formIDArray.count else { return nil }
            return formIDArray[Int(value) - 1]
        case .default:
            return value
        case .created:
            return 0xFF00_0000 | value
        case .unknown:
            return nil
        }
    }
}

nonisolated extension ESSRefID: CustomStringConvertible {
    public var description: String {
        String(format: "%06X", raw)
    }
}
