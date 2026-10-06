// The Papyrus global data table (type 1001): the script engine's string table, script
// definitions, every script instance with its variables, references, arrays, and the
// active stacks. See docs/formats/ess-papyrus.md.

import Foundation

nonisolated public struct ESSPapyrusScript: Equatable, Sendable {
    public let name: String
    /// The parent script, empty for a script with none.
    public let parent: String
    public let members: [ESSPapyrusMember]
}

nonisolated public struct ESSPapyrusMember: Equatable, Sendable {
    public let name: String
    public let type: String
}

nonisolated public struct ESSPapyrusInstance: Equatable, Sendable {
    public let id: UInt64
    public let scriptName: String
    /// The form the script is attached to.
    public let form: ESSRefID
    /// Filled from the instance's data block, in the order the save lists them.
    public internal(set) var variables: [ESSPapyrusValue] = []
}

/// A struct-like object the VM keeps apart from scripts, such as a quest alias.
nonisolated public struct ESSPapyrusReference: Equatable, Sendable {
    public let id: UInt64
    public let type: String
    public internal(set) var variables: [ESSPapyrusValue] = []
}

nonisolated public struct ESSPapyrusArray: Equatable, Sendable {
    public let id: UInt64
    public let element: ESSPapyrusElementKind
    public let length: Int
    public internal(set) var elements: [ESSPapyrusValue] = []
}

nonisolated public struct ESSPapyrusSuspendedStack: Equatable, Sendable {
    public let id: UInt32
    public let scriptName: String?
}

nonisolated public struct ESSPapyrusActiveScript: Equatable, Sendable {
    public let id: UInt32
    public let type: UInt8
}

nonisolated public struct ESSPapyrus: Equatable, Sendable {
    public let vmVersion: UInt16
    public let strings: [String]
    public let scripts: [ESSPapyrusScript]
    public internal(set) var instances: [ESSPapyrusInstance]
    public internal(set) var references: [ESSPapyrusReference]
    public internal(set) var arrays: [ESSPapyrusArray]
    /// Running and suspended stacks. OpenSky's VM cannot take them over.
    public let activeScripts: [ESSPapyrusActiveScript]
    /// The script each active stack runs, by stack id, where its frames were read.
    public internal(set) var activeScriptNames: [UInt32: String] = [:]
    /// Suspended stacks, both lists, with the script each one calls where it is named.
    public internal(set) var suspendedStacks: [ESSPapyrusSuspendedStack] = []
    /// How far the active stack data was read; everything before it is complete.
    public internal(set) var stackStatus = ESSDecodeStatus.complete
    /// Bytes per object and array id. UESP documents 4; a wider save reads as 8.
    public let idWidth: Int

    /// Tries 4-byte ids, then 8-byte ids, and keeps the first that reads cleanly.
    public init(data: Data) throws(ESSError) {
        do throws(ESSError) {
            self = try Self(data: data, idWidth: 4)
        } catch {
            guard let wide = try? Self(data: data, idWidth: 8) else { throw error }
            self = wide
        }
    }

    public init(data: Data, idWidth: Int) throws(ESSError) {
        var reader = ESSReader(data)
        vmVersion = try reader.uint16("papyrus header")
        let stringCount = try Int(reader.uint16("papyrus string count"))
        var strings: [String] = []
        for _ in 0 ..< stringCount {
            try strings.append(reader.wstring("papyrus string"))
        }
        self.strings = strings
        self.idWidth = idWidth
        let context = ESSPapyrusContext(strings: strings, idWidth: idWidth)
        scripts = try Self.readScripts(&reader, context)
        instances = try Self.readInstances(&reader, context)
        references = try Self.readReferences(&reader, context)
        arrays = try Self.readArrayInfo(&reader, context)
        _ = try reader.uint32("papyrus next active id")
        activeScripts = try Self.readActiveScripts(&reader)
        try readData(&reader, context)
        stackStatus = ESSPapyrusStacks.read(&reader, context, into: &self)
    }

    public func instances(on form: ESSRefID) -> [ESSPapyrusInstance] {
        instances.filter { $0.form == form }
    }

    public func script(named name: String) -> ESSPapyrusScript? {
        let key = name.lowercased()
        return scripts.first { $0.name.lowercased() == key }
    }

    private static func readScripts(
        _ reader: inout ESSReader, _ context: ESSPapyrusContext
    ) throws(ESSError) -> [ESSPapyrusScript] {
        let count = try reader.count32("papyrus scripts", minimumElementSize: 8)
        var scripts: [ESSPapyrusScript] = []
        for _ in 0 ..< count {
            let name = try context.string(&reader, "script name")
            let parent = try context.string(&reader, "script parent")
            let memberCount = try reader.count32("script members", minimumElementSize: 4)
            var members: [ESSPapyrusMember] = []
            for _ in 0 ..< memberCount {
                try members.append(ESSPapyrusMember(
                    name: context.string(&reader, "member name"),
                    type: context.string(&reader, "member type")
                ))
            }
            scripts.append(ESSPapyrusScript(name: name, parent: parent, members: members))
        }
        return scripts
    }

    private static func readInstances(
        _ reader: inout ESSReader, _ context: ESSPapyrusContext
    ) throws(ESSError) -> [ESSPapyrusInstance] {
        let count = try reader.count32("script instances", minimumElementSize: 12)
        var instances: [ESSPapyrusInstance] = []
        for _ in 0 ..< count {
            let id = try context.id(&reader, "script instance id")
            let name = try context.string(&reader, "script instance name")
            try reader.skip(4, "script instance")
            let form = try reader.refID("script instance form")
            _ = try reader.uint8("script instance")
            instances.append(ESSPapyrusInstance(id: id, scriptName: name, form: form))
        }
        return instances
    }

    private static func readReferences(
        _ reader: inout ESSReader, _ context: ESSPapyrusContext
    ) throws(ESSError) -> [ESSPapyrusReference] {
        let count = try reader.count32("papyrus references", minimumElementSize: 6)
        var references: [ESSPapyrusReference] = []
        for _ in 0 ..< count {
            try references.append(ESSPapyrusReference(
                id: context.id(&reader, "reference id"),
                type: context.string(&reader, "reference type")
            ))
        }
        return references
    }

    private static func readArrayInfo(
        _ reader: inout ESSReader, _ context: ESSPapyrusContext
    ) throws(ESSError) -> [ESSPapyrusArray] {
        let count = try reader.count32("papyrus arrays", minimumElementSize: 9)
        var arrays: [ESSPapyrusArray] = []
        for _ in 0 ..< count {
            let id = try context.id(&reader, "array id")
            let rawType = try reader.uint8("array type")
            guard let element = ESSPapyrusElementKind(rawValue: rawType) else {
                throw .invalidValue(context: "array element type \(rawType)")
            }
            if element == .object {
                _ = try context.string(&reader, "array object type")
            }
            let length = try reader.count32("array length", minimumElementSize: 0)
            arrays.append(ESSPapyrusArray(id: id, element: element, length: length))
        }
        return arrays
    }

    private static func readActiveScripts(
        _ reader: inout ESSReader
    ) throws(ESSError) -> [ESSPapyrusActiveScript] {
        let count = try reader.count32("active scripts", minimumElementSize: 5)
        var scripts: [ESSPapyrusActiveScript] = []
        for _ in 0 ..< count {
            try scripts.append(ESSPapyrusActiveScript(
                id: reader.uint32("active script id"), type: reader.uint8("active script type")
            ))
        }
        return scripts
    }

    /// Variable blocks, in the same order as the instance, reference, and array lists.
    private mutating func readData(
        _ reader: inout ESSReader, _ context: ESSPapyrusContext
    ) throws(ESSError) {
        for index in instances.indices {
            instances[index].variables = try Self.readObjectData(
                &reader, context, expectedID: instances[index].id, "script data"
            )
        }
        for index in references.indices {
            references[index].variables = try Self.readObjectData(
                &reader, context, expectedID: references[index].id, "reference data"
            )
        }
        for index in arrays.indices {
            guard try context.id(&reader, "array data id") == arrays[index].id else {
                throw .invalidValue(context: "array data out of order at \(index)")
            }
            arrays[index].elements = try context.values(&reader, count: arrays[index].length)
        }
    }

    private static func readObjectData(
        _ reader: inout ESSReader, _ context: ESSPapyrusContext, expectedID: UInt64,
        _ label: String
    ) throws(ESSError) -> [ESSPapyrusValue] {
        guard try context.id(&reader, "\(label) id") == expectedID else {
            throw .invalidValue(context: "\(label) out of order")
        }
        let flag = try reader.uint8("\(label) flag")
        _ = try context.string(&reader, "\(label) type")
        try reader.skip(flag & 0x04 != 0 ? 8 : 4, label)
        let count = try reader.count32("\(label) members", minimumElementSize: 5)
        return try context.values(&reader, count: count)
    }
}
