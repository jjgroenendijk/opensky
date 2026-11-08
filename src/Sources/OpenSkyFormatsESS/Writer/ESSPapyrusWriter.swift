// Writes the Papyrus global data table (type 1001): script definitions and instances
// with their variables. OpenSky writes no references, arrays, or stacks, so every
// later section is an empty list. See docs/formats/ess-papyrus.md#writing.

import Foundation

nonisolated public struct ESSPapyrusWriter: Sendable {
    public var scripts: [ESSPapyrusScript]
    /// Each instance's variables in member order: parents first, then the script's own.
    public var instances: [ESSPapyrusInstance]

    /// The VM version in the table header. Version 4 adds the queued unbind list.
    public static let vmVersion: UInt16 = 4
    /// The second part's version field. Unconfirmed: no open source gives the value.
    public static let saveFileVersion: Int16 = 1
    /// Array counts in the table's second part, all written as zero.
    static let trailingCounts = 21

    public init(scripts: [ESSPapyrusScript] = [], instances: [ESSPapyrusInstance] = []) {
        self.scripts = scripts
        self.instances = instances
    }

    public func table() throws(ESSError) -> ESSGlobalData {
        var strings = StringTable()
        let body = try bodyData(&strings)
        let data = try ESSWriter.build { writer throws(ESSError) in
            writer.uint16(Self.vmVersion)
            guard strings.names.count <= Int(UInt16.max) else {
                throw .invalidCount(context: "papyrus strings", count: strings.names.count)
            }
            writer.uint16(UInt16(strings.names.count))
            for name in strings.names {
                try writer.wstring(name, "papyrus string")
            }
            writer.bytes(body)
        }
        return ESSGlobalData(type: ESSGlobalDataType.papyrus.rawValue, data: data)
    }

    private func bodyData(_ strings: inout StringTable) throws(ESSError) -> Data {
        var writer = ESSWriter()
        try writer.count32(scripts.count, "papyrus scripts")
        for script in scripts {
            try strings.write(script.name, &writer)
            try strings.write(script.parent, &writer)
            try writer.count32(script.members.count, "script members")
            for member in script.members {
                try strings.write(member.name, &writer)
                try strings.write(member.type, &writer)
            }
        }
        try writer.count32(instances.count, "script instances")
        for instance in instances {
            try Self.id(instance.id, &writer)
            try strings.write(instance.scriptName, &writer)
            // Two unknown words; -1 in the second would mean the form is ignored.
            writer.uint32(0)
            writer.refID(instance.form)
            writer.uint8(0)
        }
        // References, arrays, the next active id, and active scripts.
        writer.uint32(0)
        writer.uint32(0)
        writer.uint32(1)
        writer.uint32(0)
        for instance in instances {
            try Self.id(instance.id, &writer)
            writer.uint8(0)
            try strings.write(instance.scriptName, &writer)
            writer.uint32(0)
            try writer.count32(instance.variables.count, "script data members")
            for value in instance.variables {
                try Self.value(value, &strings, &writer)
            }
        }
        // Function messages, two suspended stack lists, an unknown word, unknown ids,
        // queued unbinds, then the second part: its version and its array counts.
        writer.bytes(Data(count: 6 * 4))
        writer.int16(Self.saveFileVersion)
        writer.bytes(Data(count: Self.trailingCounts * 4))
        return writer.data
    }

    private static func id(_ id: UInt64, _ writer: inout ESSWriter) throws(ESSError) {
        guard let narrow = UInt32(exactly: id) else {
            throw .invalidValue(context: "papyrus id \(id) does not fit 4 bytes")
        }
        writer.uint32(narrow)
    }

    private static func value(
        _ value: ESSPapyrusValue, _ strings: inout StringTable, _ writer: inout ESSWriter
    ) throws(ESSError) {
        switch value {
        case .null:
            writer.uint8(0)
            writer.uint32(0)
        case let .object(type, id):
            writer.uint8(1)
            try strings.write(type, &writer)
            try Self.id(id, &writer)
        case let .string(text):
            writer.uint8(2)
            try strings.write(text, &writer)
        case let .integer(number):
            writer.uint8(3)
            writer.int32(number)
        case let .float(number):
            writer.uint8(4)
            writer.float32(number)
        case let .boolean(flag):
            writer.uint8(5)
            writer.uint32(flag ? 1 : 0)
        case let .array(element, type, id):
            writer.uint8(element.rawValue + 10)
            if element == .object {
                try strings.write(type ?? "", &writer)
            }
            try Self.id(id, &writer)
        }
    }
}

/// Interned strings in first-use order, so the same input writes the same table.
nonisolated private struct StringTable {
    var names: [String] = []
    var indices: [String: Int] = [:]

    mutating func write(_ text: String, _ writer: inout ESSWriter) throws(ESSError) {
        let index: Int
        if let known = indices[text] {
            index = known
        } else {
            index = names.count
            names.append(text)
            indices[text] = index
        }
        guard index <= Int(UInt16.max) else {
            throw .invalidCount(context: "papyrus strings", count: index + 1)
        }
        writer.uint16(UInt16(index))
    }
}
