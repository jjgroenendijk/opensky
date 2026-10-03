// Havok binary tagfile (`.hkt`): a self-describing stream of class definitions
// and objects, read without any knowledge of Havok class layouts.
// Byte map and the evidence for it: docs/formats/hkt-tagfile.md.

import Foundation

nonisolated public enum HKTError: Error, Equatable, Sendable {
    /// The first two u32s are not the tagfile magic pair.
    case badMagic(found0: UInt32, found1: UInt32)
    case truncated(offset: Int)
    case varintTooLong(offset: Int)
    case unknownTag(Int, offset: Int)
    case badStringReference(Int, offset: Int)
    case badClassIndex(Int, offset: Int)
    case badMemberType(Int, offset: Int)
    /// A count larger than the bytes left, so it cannot be real.
    case countOutOfRange(Int, offset: Int)
    case unknownStructClass(String, offset: Int)
    case nestingTooDeep(offset: Int)
}

/// The base kind of a member, from the low nibble of its type word.
nonisolated public enum HKTBaseType: Int, Equatable, Sendable {
    case void = 0
    case byte = 1
    case int = 2
    case real = 3
    case vector4 = 4
    case vector8 = 5
    case vector12 = 6
    case vector16 = 7
    case object = 8
    case structure = 9
    case string = 10

    /// Float count of a vector kind, nil for every other kind.
    public var vectorLength: Int? {
        switch self {
        case .vector4: 4
        case .vector8: 8
        case .vector12: 12
        case .vector16: 16
        default: nil
        }
    }
}

nonisolated public struct HKTMemberType: Equatable, Sendable {
    public let base: HKTBaseType
    public let isArray: Bool
    /// Fixed element count when the type word has the tuple bit.
    public let tupleCount: Int?
    /// The class an object or struct member names.
    public let className: String?
}

nonisolated public struct HKTMember: Equatable, Sendable {
    public let name: String
    public let type: HKTMemberType
}

/// One class definition. `parent` indexes `HKTagfile.classes`; members are the
/// class's own, without the inherited ones.
nonisolated public struct HKTClass: Equatable, Sendable {
    public let name: String
    public let version: Int
    public let parent: Int?
    public let members: [HKTMember]
}

/// A pointer member. A version 3 file names a remembered object by its index;
/// a version 0 file writes the object in place.
nonisolated public enum HKTReference: Equatable, Sendable {
    case null
    case remembered(Int)
    case object(Int)
}

indirect nonisolated public enum HKTValue: Equatable, Sendable {
    case byte(UInt8)
    case int(Int64)
    case real(Float)
    case vector([Float])
    case string(String?)
    case reference(HKTReference)
    case structure(HKTFields)
    case array([HKTValue])
}

/// The members one object or struct wrote, in class order. Members the
/// presence mask left out are absent.
nonisolated public struct HKTFields: Equatable, Sendable {
    public let classIndex: Int
    public let values: [(name: String, value: HKTValue)]

    public init(classIndex: Int, values: [(name: String, value: HKTValue)]) {
        self.classIndex = classIndex
        self.values = values
    }

    public subscript(name: String) -> HKTValue? {
        values.first { $0.name == name }?.value
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.classIndex == rhs.classIndex
            && lhs.values.map(\.name) == rhs.values.map(\.name)
            && lhs.values.map(\.value) == rhs.values.map(\.value)
    }
}

nonisolated public struct HKTagfile: Sendable {
    public static let magic0: UInt32 = 0xCAB0_0D1E
    public static let magic1: UInt32 = 0xD011_FACE

    /// The value of the file-info item: 0 or 3 on the install.
    public let version: Int
    /// Index 0 is unused, as on disk, so a parent index of 0 means none.
    public let classes: [HKTClass]
    /// Every object in read order.
    public let objects: [HKTFields]
    /// Object index per remembered index; index 0 is null.
    public let remembered: [Int?]
    /// Version 0 files end after their last object with no end item.
    public let hasEndTag: Bool
    /// Int arrays whose leading varint was not the 4 every vanilla file writes.
    public let unexpectedIntArrayHeaders: Int

    public init(data: Data) throws {
        var reader = HKTReader(data: data)
        try reader.readMagic()
        try reader.readItems()
        version = reader.version
        classes = reader.classes
        objects = reader.objects
        remembered = reader.remembered
        hasEndTag = reader.sawEndTag
        unexpectedIntArrayHeaders = reader.unexpectedIntArrayHeaders
    }

    public func className(of object: HKTFields) -> String {
        classes.indices.contains(object.classIndex)
            ? classes[object.classIndex].name : "<unknown>"
    }

    /// The object a reference names, or nil for null or a dangling index.
    public func object(_ reference: HKTReference) -> HKTFields? {
        switch reference {
        case .null:
            return nil
        case let .object(index):
            return objects.indices.contains(index) ? objects[index] : nil
        case let .remembered(index):
            guard remembered.indices.contains(index), let object = remembered[index] else {
                return nil
            }
            return objects[object]
        }
    }

    /// Own and inherited members of a class, base class first.
    public func allMembers(ofClass index: Int) -> [HKTMember] {
        var chain: [HKTMember] = []
        var current: Int? = index
        var seen: Set<Int> = []
        while let next = current, classes.indices.contains(next), seen.insert(next).inserted {
            chain = classes[next].members + chain
            current = classes[next].parent
        }
        return chain
    }
}
