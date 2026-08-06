// Object, variable, property and state sections of the PEX decoder.

import Foundation

nonisolated extension PexDecoder {
    mutating func decodeObjects() throws -> [PexObject] {
        let count = try Int(reader.readUInt16())
        var result: [PexObject] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            let name = try resolve(reader.readUInt16())
            let storedSize = try reader.readUInt32()
            guard storedSize >= 4 else {
                throw PexError.invalidObjectSize(storedSize)
            }
            var objectReader = try reader.subreader(count: Int(storedSize - 4))
            let object = try decodeObject(name: name, from: &objectReader)
            guard objectReader.bytesRemaining == 0 else {
                throw PexError.objectSizeMismatch(
                    name: name,
                    remaining: objectReader.bytesRemaining
                )
            }
            result.append(object)
        }
        return result
    }

    private mutating func decodeObject(
        name: String,
        from objectReader: inout PexReader
    ) throws -> PexObject {
        let parent = try resolve(objectReader.readUInt16())
        let documentation = try resolve(objectReader.readUInt16())
        let userFlags = try objectReader.readUInt32()
        let automaticState = try resolve(objectReader.readUInt16())
        let variables = try decodeVariables(from: &objectReader)
        let properties = try decodeProperties(from: &objectReader)
        let states = try decodeStates(from: &objectReader)
        return PexObject(
            name: name,
            parentClassName: parent,
            documentation: documentation,
            userFlags: userFlags,
            automaticStateName: automaticState,
            variables: variables,
            properties: properties,
            states: states
        )
    }

    private mutating func decodeVariables(
        from objectReader: inout PexReader
    ) throws -> [PexVariable] {
        let count = try Int(objectReader.readUInt16())
        var result: [PexVariable] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            try result.append(PexVariable(
                name: resolve(objectReader.readUInt16()),
                typeName: resolve(objectReader.readUInt16()),
                userFlags: objectReader.readUInt32(),
                initialValue: decodeValue(from: &objectReader)
            ))
        }
        return result
    }

    private mutating func decodeProperties(
        from objectReader: inout PexReader
    ) throws -> [PexProperty] {
        let count = try Int(objectReader.readUInt16())
        var result: [PexProperty] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            let name = try resolve(objectReader.readUInt16())
            let typeName = try resolve(objectReader.readUInt16())
            let documentation = try resolve(objectReader.readUInt16())
            let userFlags = try objectReader.readUInt32()
            let flags = try PexPropertyFlags(rawValue: objectReader.readUInt8())
            let automaticName = flags.contains(.automatic)
                ? try resolve(objectReader.readUInt16())
                : nil
            let readHandler = flags.contains(.readable) && !flags.contains(.automatic)
                ? try decodeFunction(from: &objectReader)
                : nil
            let writeHandler = flags.contains(.writable) && !flags.contains(.automatic)
                ? try decodeFunction(from: &objectReader)
                : nil
            result.append(PexProperty(
                name: name,
                typeName: typeName,
                documentation: documentation,
                userFlags: userFlags,
                flags: flags,
                automaticVariableName: automaticName,
                readHandler: readHandler,
                writeHandler: writeHandler
            ))
        }
        return result
    }

    private mutating func decodeStates(from objectReader: inout PexReader) throws -> [PexState] {
        let count = try Int(objectReader.readUInt16())
        var result: [PexState] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            let name = try resolve(objectReader.readUInt16())
            let functionCount = try Int(objectReader.readUInt16())
            var functions: [PexNamedFunction] = []
            functions.reserveCapacity(functionCount)
            for _ in 0 ..< functionCount {
                let functionName = try resolve(objectReader.readUInt16())
                let function = try decodeFunction(from: &objectReader)
                functions.append(PexNamedFunction(name: functionName, function: function))
            }
            result.append(PexState(name: name, functions: functions))
        }
        return result
    }
}
