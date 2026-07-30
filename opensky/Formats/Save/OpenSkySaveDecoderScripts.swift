// PSCR chunk decoding for the OpenSky native save container (issue #171):
// Papyrus script instance identity, active state, and variable values.
//
// The payload arrives as its own `Data`, exactly like `RDLT`, so the chunk's
// declared length bounds every read in here and a corrupt count inside the
// chunk can never walk into the next chunk's bytes. Both declared counts — the
// instance count and each instance's variable count — go through
// `OpenSkySaveDecoder.validate(count:minimumElementSize:remaining:chunk:)`
// before anything reserves storage.

import Foundation

nonisolated enum OpenSkySaveScriptDecoder {
    /// `PSCR` chunk: an instance count, then one entry per live script
    /// instance.
    static func decodeScripts(_ payload: Data) throws -> [PapyrusInstanceState] {
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

    /// A tag byte plus the value's payload.
    ///
    /// Non-finite float policy, chosen here rather than in the encoder: a
    /// NaN or infinite float is **normalized to zero**, not rejected. Papyrus
    /// arithmetic can legitimately produce one (a division by zero in a mod
    /// script is not corruption), and refusing to load a whole world because
    /// one script variable drifted out of range would be the worse failure.
    /// The value is therefore clamped on the way in and the rest of the save
    /// loads. An unknown tag byte is still an error: that is a shape this
    /// build cannot interpret at all.
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
