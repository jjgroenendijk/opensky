// Papyrus table values: one typed variable as the save stores it.
// See docs/formats/ess-papyrus.md#variables.

import Foundation

nonisolated public enum ESSPapyrusValue: Equatable, Sendable {
    case null
    /// An object handle: the script type and the id of a script instance or reference.
    case object(type: String, id: UInt64)
    case string(String)
    case integer(Int32)
    case float(Float)
    case boolean(Bool)
    /// An array: its element kind, the object type for object arrays, and its id.
    case array(element: ESSPapyrusElementKind, type: String?, id: UInt64)

    public var kindName: String {
        switch self {
        case .null: "none"
        case .object: "object"
        case .string: "string"
        case .integer: "int"
        case .float: "float"
        case .boolean: "bool"
        case .array: "array"
        }
    }
}

nonisolated public enum ESSPapyrusElementKind: UInt8, Sendable {
    case object = 1
    case string = 2
    case integer = 3
    case float = 4
    case boolean = 5
}

/// Reads string table references and variables with the table's id width.
nonisolated struct ESSPapyrusContext {
    let strings: [String]
    /// Bytes per object and array id: 4, or 8 if the save uses wide ids.
    let idWidth: Int

    func string(_ reader: inout ESSReader, _ context: String) throws(ESSError) -> String {
        let index = try Int(reader.uint16(context))
        guard index < strings.count else {
            throw .invalidValue(context: "\(context) names string \(index) of \(strings.count)")
        }
        return strings[index]
    }

    func id(_ reader: inout ESSReader, _ context: String) throws(ESSError) -> UInt64 {
        idWidth == 8 ? try reader.uint64(context) : try UInt64(reader.uint32(context))
    }

    func value(_ reader: inout ESSReader) throws(ESSError) -> ESSPapyrusValue {
        let type = try reader.uint8("variable type")
        switch type {
        case 0:
            try reader.skip(4, "null variable")
            return .null
        case 1:
            return try .object(type: string(&reader, "object type"), id: id(&reader, "object id"))
        case 2: return try .string(string(&reader, "string variable"))
        case 3: return try .integer(reader.int32("int variable"))
        case 4: return try .float(reader.float32("float variable"))
        case 5: return try .boolean(reader.uint32("bool variable") != 0)
        case 11:
            let objectType = try string(&reader, "object array type")
            return try .array(element: .object, type: objectType, id: id(&reader, "array id"))
        case 12 ... 15:
            guard let element = ESSPapyrusElementKind(rawValue: type - 10) else {
                throw .invalidValue(context: "variable type \(type)")
            }
            return try .array(element: element, type: nil, id: id(&reader, "array id"))
        default:
            throw .invalidValue(context: "variable type \(type)")
        }
    }

    /// One array element: the array's kind decides the layout, with a type byte first.
    func values(
        _ reader: inout ESSReader, count: Int
    ) throws(ESSError) -> [ESSPapyrusValue] {
        guard count * 5 <= reader.bytesRemaining else {
            throw .invalidCount(context: "variables", count: count)
        }
        var values: [ESSPapyrusValue] = []
        values.reserveCapacity(count)
        for _ in 0 ..< count {
            try values.append(value(&reader))
        }
        return values
    }
}
