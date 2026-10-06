// A synthetic Papyrus global data table (type 1001), built in code with an interned
// string table. Layout: docs/formats/ess-papyrus.md.

import Foundation
import OpenSkyFormatsCore

public enum ESSPapyrusFixtureValue {
    case null
    case object(type: String, id: UInt64)
    case string(String)
    case integer(Int32)
    case float(Float)
    case boolean(Bool)
    /// `kind` is the variable type byte, 11 to 15.
    case array(kind: UInt8, type: String?, id: UInt64)
}

public struct ESSPapyrusFixtureScript {
    public var name: String
    public var parent: String
    public var members: [(name: String, type: String)]

    public init(name: String, parent: String = "", members: [(name: String, type: String)]) {
        self.name = name
        self.parent = parent
        self.members = members
    }
}

public struct ESSPapyrusFixtureInstance {
    public var id: UInt64
    public var script: String
    /// The attached form as a ref id kind and value.
    public var form: (kind: UInt8, value: UInt32)
    public var variables: [ESSPapyrusFixtureValue]

    public init(
        id: UInt64, script: String, form: (kind: UInt8, value: UInt32),
        variables: [ESSPapyrusFixtureValue]
    ) {
        self.id = id
        self.script = script
        self.form = form
        self.variables = variables
    }
}

public struct ESSPapyrusFixtureArray {
    public var id: UInt64
    /// 1 object, 2 string, 3 int, 4 float, 5 bool.
    public var element: UInt8
    public var objectType: String?
    public var values: [ESSPapyrusFixtureValue]

    public init(
        id: UInt64,
        element: UInt8,
        objectType: String? = nil,
        values: [ESSPapyrusFixtureValue]
    ) {
        self.id = id
        self.element = element
        self.objectType = objectType
        self.values = values
    }
}

public struct ESSPapyrusFixture {
    public var idWidth = 4
    public var scripts: [ESSPapyrusFixtureScript] = []
    public var instances: [ESSPapyrusFixtureInstance] = []
    public var arrays: [ESSPapyrusFixtureArray] = []
    /// Active stack ids. Each has one frame running `script` with no instructions.
    public var activeStacks: [(id: UInt32, script: String)] = []
    public var suspendedStacks: [(id: UInt32, script: String)] = []
    /// A named owner of each active stack, written with owner kind 1, and its fixed tail.
    public var stackOwner: (name: String, tail: Int)?
    /// Raw instructions of each active stack's frame.
    public var instructions: [Data] = []
    /// Function messages, each naming a script.
    public var functionMessages: [String] = []
    private var strings: [String] = []

    public init() {}

    public mutating func build() -> Data {
        let body = bodyBytes()
        var writer = BinaryWriter()
        writer.writeUInt16(4)
        writer.writeUInt16(UInt16(strings.count))
        strings.forEach { ESSBytes.wstring($0, into: &writer) }
        writer.write(body)
        return writer.data
    }

    private mutating func bodyBytes() -> Data {
        var writer = BinaryWriter()
        writer.writeUInt32(UInt32(scripts.count))
        for script in scripts {
            writeString(script.name, &writer)
            writeString(script.parent, &writer)
            writer.writeUInt32(UInt32(script.members.count))
            for member in script.members {
                writeString(member.name, &writer)
                writeString(member.type, &writer)
            }
        }
        writer.writeUInt32(UInt32(instances.count))
        for instance in instances {
            writeID(instance.id, &writer)
            writeString(instance.script, &writer)
            writer.writeUInt32(0)
            ESSBytes.refID(kind: instance.form.kind, value: instance.form.value, into: &writer)
            writer.writeUInt8(0)
        }
        writer.writeUInt32(0)
        writeArrayInfo(&writer)
        writer.writeUInt32(1)
        writer.writeUInt32(UInt32(activeStacks.count))
        for stack in activeStacks {
            writer.writeUInt32(stack.id)
            writer.writeUInt8(0)
        }
        writeData(&writer)
        writeStacks(&writer)
        return writer.data
    }

    private mutating func writeArrayInfo(_ writer: inout BinaryWriter) {
        writer.writeUInt32(UInt32(arrays.count))
        for array in arrays {
            writeID(array.id, &writer)
            writer.writeUInt8(array.element)
            if array.element == 1 {
                writeString(array.objectType ?? "", &writer)
            }
            writer.writeUInt32(UInt32(array.values.count))
        }
    }

    private mutating func writeData(_ writer: inout BinaryWriter) {
        for instance in instances {
            writeID(instance.id, &writer)
            writer.writeUInt8(0)
            writeString(instance.script, &writer)
            writer.writeUInt32(0)
            writer.writeUInt32(UInt32(instance.variables.count))
            instance.variables.forEach { writeValue($0, &writer) }
        }
        for array in arrays {
            writeID(array.id, &writer)
            array.values.forEach { writeValue($0, &writer) }
        }
    }

    private mutating func writeStacks(_ writer: inout BinaryWriter) {
        for stack in activeStacks {
            writer.writeUInt32(stack.id)
            writer.writeUInt8(3)
            writer.writeUInt8(1)
            writeValue(.null, &writer)
            writer.write(Data([0, 0]))
            writeOwner(&writer)
            writer.writeUInt32(1)
            writer.writeUInt32(0)
            writer.writeUInt8(1)
            writer.writeUInt8(0)
            writeString(stack.script, &writer)
            writeString(stack.script, &writer)
            writeString("OnUpdate", &writer)
            writer.write(Data(count: 2 + 2 + 2 + 4 + 1 + 2 + 2))
            writer.writeUInt16(UInt16(instructions.count))
            instructions.forEach { writer.write($0) }
            writer.writeUInt32(0)
            writeValue(.null, &writer)
            writer.writeUInt8(0)
        }
        writer.writeUInt32(UInt32(functionMessages.count))
        for script in functionMessages {
            writer.writeUInt8(0)
            writer.writeUInt32(1)
            writer.writeUInt8(1)
            writer.writeUInt8(0)
            writeString(script, &writer)
            writeString("OnInit", &writer)
            writeValue(.null, &writer)
            writer.writeUInt32(0)
        }
        writer.writeUInt32(UInt32(suspendedStacks.count))
        for stack in suspendedStacks {
            writer.writeUInt32(stack.id)
            writer.writeUInt8(1)
            writer.writeUInt8(0)
            writeString(stack.script, &writer)
            writeString("OnUpdate", &writer)
            writeValue(.null, &writer)
            writer.writeUInt32(0)
        }
        writer.writeUInt32(0)
    }

    private func writeOwner(_ writer: inout BinaryWriter) {
        guard let owner = stackOwner else {
            writer.writeUInt8(0)
            return
        }
        writer.writeUInt8(1)
        writer.writeUInt32(UInt32(owner.name.utf8.count))
        writer.write(Data(owner.name.utf8))
        writer.write(Data(count: owner.tail))
    }

    private mutating func writeValue(
        _ value: ESSPapyrusFixtureValue,
        _ writer: inout BinaryWriter
    ) {
        switch value {
        case .null:
            writer.writeUInt8(0)
            writer.writeUInt32(0)
        case let .object(type, id):
            writer.writeUInt8(1)
            writeString(type, &writer)
            writeID(id, &writer)
        case let .string(text):
            writer.writeUInt8(2)
            writeString(text, &writer)
        case let .integer(number):
            writer.writeUInt8(3)
            writer.writeUInt32(UInt32(bitPattern: number))
        case let .float(number):
            writer.writeUInt8(4)
            writer.writeFloat32(number)
        case let .boolean(flag):
            writer.writeUInt8(5)
            writer.writeUInt32(flag ? 1 : 0)
        case let .array(kind, type, id):
            writer.writeUInt8(kind)
            if kind == 11 {
                writeString(type ?? "", &writer)
            }
            writeID(id, &writer)
        }
    }

    private func writeID(_ id: UInt64, _ writer: inout BinaryWriter) {
        if idWidth == 8 {
            writer.writeUInt64(id)
        } else {
            writer.writeUInt32(UInt32(truncatingIfNeeded: id))
        }
    }

    private mutating func writeString(_ text: String, _ writer: inout BinaryWriter) {
        if let index = strings.firstIndex(of: text) {
            writer.writeUInt16(UInt16(index))
            return
        }
        strings.append(text)
        writer.writeUInt16(UInt16(strings.count - 1))
    }
}
