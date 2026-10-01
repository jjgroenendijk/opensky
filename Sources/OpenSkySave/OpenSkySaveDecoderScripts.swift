// PSCR chunk decoding: Papyrus script instances, active state and variables. The
// payload is its own `Data`, and both counts pass `OpenSkySaveDecoder.validate` before
// anything reserves storage.

import Foundation
import OpenSkyScriptingInterface

nonisolated public enum OpenSkySaveScriptDecoder: Sendable {
    /// `PSCR` chunk: an instance count, then one entry per live script
    /// instance.
    public static func decodeScripts(_ payload: Data) throws -> [PapyrusInstanceState] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("PSCR instance count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumScriptEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.papyrusScripts
        )
        var states: [PapyrusInstanceState] = []
        states.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try states.append(decodeInstance(&reader))
        }
        return states
    }

    private static func decodeInstance(
        _ reader: inout SaveReader
    ) throws -> PapyrusInstanceState {
        let reference = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let scriptName = try reader.string("PSCR script name")
        let activeState = try reader.string("PSCR active state")
        let hasFiredOnInit = try reader.bool("PSCR OnInit fired flag")
        return try PapyrusInstanceState(
            key: PapyrusInstanceKey(reference: reference, scriptName: scriptName),
            activeState: activeState,
            variables: decodeVariables(&reader),
            hasFiredOnInit: hasFiredOnInit
        )
    }

    private static func decodeVariables(
        _ reader: inout SaveReader
    ) throws -> [PapyrusVariableState] {
        let count = try reader.uint32("PSCR variable count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumScriptVariableSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.papyrusScripts
        )
        var variables: [PapyrusVariableState] = []
        variables.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let declaringScript = try reader.string("PSCR declaring script")
            let name = try reader.string("PSCR variable name")
            try variables.append(PapyrusVariableState(
                declaringScript: declaringScript,
                name: name,
                value: decodeValue(&reader)
            ))
        }
        return variables
    }

    /// A tag byte plus the value's payload. A NaN or infinite float becomes zero, because
    /// Papyrus can make one legitimately and one variable must not block a load. An
    /// unknown tag byte is still an error.
    private static func decodeValue(_ reader: inout SaveReader) throws -> PapyrusValue {
        let tag = try reader.uint8("PSCR value tag")
        switch tag {
        case OpenSkySaveFormat.ValueTag.none:
            return .none
        case OpenSkySaveFormat.ValueTag.boolean:
            return try .boolean(reader.bool("PSCR boolean value"))
        case OpenSkySaveFormat.ValueTag.integer:
            return try .integer(Int32(bitPattern: reader.uint32("PSCR integer value")))
        case OpenSkySaveFormat.ValueTag.float:
            let number = try Float(bitPattern: reader.uint32("PSCR float value"))
            return .float(number.isFinite ? number : 0)
        case OpenSkySaveFormat.ValueTag.string:
            return try .string(reader.string("PSCR string value"))
        default:
            throw OpenSkySaveError.invalidValue(context: "PSCR value tag \(tag)")
        }
    }
}
