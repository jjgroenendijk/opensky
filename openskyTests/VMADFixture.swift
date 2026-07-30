// Synthetic VMAD builder. Every byte is constructed in code from the xEdit /
// UESP layout; no game data is embedded.

import Foundation
@testable import opensky

enum VMADFixture {
    enum Value {
        case none
        case object(ScriptObjectReference)
        case string(String)
        case integer(Int32)
        case float(Float)
        case boolean(Bool)
        case objects([ScriptObjectReference])
        case strings([String])
        case integers([Int32])
        case floats([Float])
        case booleans([Bool])

        var type: UInt8 {
            switch self {
            case .none: 0
            case .object: 1
            case .string: 2
            case .integer: 3
            case .float: 4
            case .boolean: 5
            case .objects: 11
            case .strings: 12
            case .integers: 13
            case .floats: 14
            case .booleans: 15
            }
        }
    }

    struct Property {
        let name: String
        let flags: UInt8
        let value: Value

        init(_ name: String, _ value: Value, flags: UInt8 = 1) {
            self.name = name
            self.flags = flags
            self.value = value
        }
    }

    struct Script {
        let name: String
        let flags: UInt8
        let properties: [Property]

        init(_ name: String, flags: UInt8 = 0, properties: [Property]) {
            self.name = name
            self.flags = flags
            self.properties = properties
        }
    }

    static func object(
        _ formID: UInt32,
        alias: Int16 = -1,
        unused: UInt16 = 0
    ) -> ScriptObjectReference {
        ScriptObjectReference(formID: FormID(formID), alias: alias, unused: unused)
    }

    static func payload(
        version: Int16 = 5,
        objectFormat: ScriptObjectFormat = .formIDLast,
        scripts: [Script],
        tail: Data = Data()
    ) -> Data {
        var data = Data()
        data.appendUInt16(UInt16(bitPattern: version))
        data.appendUInt16(UInt16(bitPattern: objectFormat.rawValue))
        data.appendUInt16(UInt16(scripts.count))
        for script in scripts {
            data.appendVMADString(script.name)
            if version >= 4 {
                data.append(script.flags)
            }
            data.appendUInt16(UInt16(script.properties.count))
            for property in script.properties {
                data.appendVMADString(property.name)
                data.append(property.value.type)
                if version >= 4 {
                    data.append(property.flags)
                }
                data.append(property.value, objectFormat: objectFormat)
            }
        }
        data.append(tail)
        return data
    }
}

extension Data {
    fileprivate mutating func appendVMADString(_ value: String) {
        let bytes = Data(value.utf8)
        appendUInt16(UInt16(bytes.count))
        append(bytes)
    }

    fileprivate mutating func append(
        _ value: VMADFixture.Value,
        objectFormat: ScriptObjectFormat
    ) {
        switch value {
        case .none:
            break
        case let .object(value):
            append(value, objectFormat: objectFormat)
        case let .string(value):
            appendVMADString(value)
        case let .integer(value):
            appendUInt32(UInt32(bitPattern: value))
        case let .float(value):
            appendFloat32(value)
        case let .boolean(value):
            append(value ? 1 : 0)
        case let .objects(values):
            appendUInt32(UInt32(values.count))
            values.forEach { append($0, objectFormat: objectFormat) }
        case let .strings(values):
            appendUInt32(UInt32(values.count))
            values.forEach { appendVMADString($0) }
        case let .integers(values):
            appendUInt32(UInt32(values.count))
            values.forEach { appendUInt32(UInt32(bitPattern: $0)) }
        case let .floats(values):
            appendUInt32(UInt32(values.count))
            values.forEach { appendFloat32($0) }
        case let .booleans(values):
            appendUInt32(UInt32(values.count))
            values.forEach { append($0 ? 1 : 0) }
        }
    }

    fileprivate mutating func append(
        _ value: ScriptObjectReference,
        objectFormat: ScriptObjectFormat
    ) {
        switch objectFormat {
        case .formIDFirst:
            appendUInt32(value.formID.rawValue)
            appendUInt16(UInt16(bitPattern: value.alias))
            appendUInt16(value.unused)
        case .formIDLast:
            appendUInt16(value.unused)
            appendUInt16(UInt16(bitPattern: value.alias))
            appendUInt32(value.formID.rawValue)
        }
    }
}
