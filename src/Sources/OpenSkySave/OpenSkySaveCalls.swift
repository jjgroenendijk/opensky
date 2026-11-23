// PCAL chunk: the Papyrus calls that were running or waiting at the save, and the
// arrays they share. Layout: docs/formats/opensky-save-world-chunks.md#pcal.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

/// The tag bytes of a `PCAL` value, return target, and wake. The first five value tags
/// are those of `PSCR`.
nonisolated private enum CallTag {
    static let scriptInstance: UInt8 = 5
    static let reference: UInt8 = 6
    static let alias: UInt8 = 7
    static let array: UInt8 = 8

    static let returnRoot: UInt8 = 0
    static let returnDiscard: UInt8 = 1
    static let returnUnread: UInt8 = 2
    static let returnVariable: UInt8 = 3

    static let wakeRealSeconds: UInt8 = 0
    static let wakeMenuSeconds: UInt8 = 1
    static let wakeGameHours: UInt8 = 2
    static let wakeQuestFragments: UInt8 = 3
    static let wakeQuestStart: UInt8 = 4
    static let wakeLost: UInt8 = 5

    static let hasOwner: UInt8 = 1 << 0
    static let holdsInstance: UInt8 = 1 << 1
}

nonisolated enum OpenSkySaveCallWriter {
    static func write(_ snapshot: PapyrusCallSnapshot, into writer: inout BinaryWriter) {
        guard !snapshot.isEmpty else { return }
        writer.writeChunk(tag: OpenSkySaveFormat.ChunkTag.papyrusCalls) { payload in
            payload.writeUInt32(UInt32(clamping: snapshot.arrays.count))
            for array in snapshot.arrays {
                payload.writeString(array.elementType)
                writeValues(array.elements, into: &payload)
            }
            payload.writeUInt32(UInt32(clamping: snapshot.calls.count))
            for call in snapshot.calls {
                writeCall(call, into: &payload)
            }
        }
    }

    private static func writeCall(_ call: PapyrusCallState, into writer: inout BinaryWriter) {
        let flags = (call.owner == nil ? 0 : CallTag.hasOwner)
            | (call.holdsInstance ? CallTag.holdsInstance : 0)
        writer.writeUInt8(flags)
        if let owner = call.owner {
            writeInstance(owner, into: &writer)
        }
        writer.writeString(call.nativeScript)
        writer.writeString(call.nativeFunction)
        writer.writeString(call.returnType)
        writeWake(call.wake, into: &writer)
        writeReturn(call.resume, into: &writer)
        writer.writeUInt32(UInt32(clamping: call.frames.count))
        for frame in call.frames {
            writer.writeString(frame.script)
            writer.writeUInt32(UInt32(clamping: frame.functionOrdinal))
            writer.writeUInt32(UInt32(clamping: frame.instructionCount))
            writer.writeUInt8(frame.instance == nil ? 0 : 1)
            if let instance = frame.instance {
                writeInstance(instance, into: &writer)
            }
            writeReturn(frame.completion, into: &writer)
            writer.writeUInt32(UInt32(clamping: frame.instructionIndex))
            writeValues(frame.slots, into: &writer)
        }
    }

    private static func writeInstance(_ key: PapyrusInstanceKey, into writer: inout BinaryWriter) {
        writer.writeKey(key.reference)
        writer.writeString(key.scriptName)
    }

    private static func writeReturn(_ target: PapyrusSavedReturn, into writer: inout BinaryWriter) {
        switch target {
        case .root: writer.writeUInt8(CallTag.returnRoot)
        case .discard: writer.writeUInt8(CallTag.returnDiscard)
        case .assign(nil): writer.writeUInt8(CallTag.returnUnread)
        case let .assign(name?):
            writer.writeUInt8(CallTag.returnVariable)
            writer.writeString(name)
        }
    }

    private static func writeWake(_ wake: PapyrusSavedWake, into writer: inout BinaryWriter) {
        switch wake {
        case let .realSeconds(seconds, answer):
            writer.writeUInt8(CallTag.wakeRealSeconds)
            writer.writeUInt64(seconds.bitPattern)
            writer.writeUInt8(answer == nil ? 0 : 1)
            if let answer {
                writeValue(answer, into: &writer)
            }
        case let .menuSeconds(seconds):
            writer.writeUInt8(CallTag.wakeMenuSeconds)
            writer.writeUInt64(seconds.bitPattern)
        case let .gameHours(hours):
            writer.writeUInt8(CallTag.wakeGameHours)
            writer.writeUInt64(hours.bitPattern)
        case let .questFragments(quest, answer):
            writer.writeUInt8(CallTag.wakeQuestFragments)
            writer.writeKey(quest)
            writeValue(answer, into: &writer)
        case let .questStart(quest, thenFragments):
            writer.writeUInt8(CallTag.wakeQuestStart)
            writer.writeKey(quest)
            writer.writeUInt8(thenFragments ? 1 : 0)
        case .lost:
            writer.writeUInt8(CallTag.wakeLost)
        }
    }

    private static func writeValues(
        _ values: [PapyrusSavedValue],
        into writer: inout BinaryWriter
    ) {
        writer.writeUInt32(UInt32(clamping: values.count))
        for value in values {
            writeValue(value, into: &writer)
        }
    }

    private static func writeValue(_ value: PapyrusSavedValue, into writer: inout BinaryWriter) {
        switch value {
        case .none:
            OpenSkySaveEncoder.writeScriptValue(.none, into: &writer)
        case let .boolean(flag):
            OpenSkySaveEncoder.writeScriptValue(.boolean(flag), into: &writer)
        case let .integer(number):
            OpenSkySaveEncoder.writeScriptValue(.integer(number), into: &writer)
        case let .float(number):
            OpenSkySaveEncoder.writeScriptValue(.float(number), into: &writer)
        case let .string(text):
            OpenSkySaveEncoder.writeScriptValue(.string(text), into: &writer)
        case let .instance(key):
            writer.writeUInt8(CallTag.scriptInstance)
            writeInstance(key, into: &writer)
        case let .reference(key):
            writer.writeUInt8(CallTag.reference)
            writer.writeKey(key)
        case let .alias(quest, id):
            writer.writeUInt8(CallTag.alias)
            writer.writeKey(quest)
            writer.writeUInt32(id)
        case let .array(index):
            writer.writeUInt8(CallTag.array)
            writer.writeUInt32(UInt32(clamping: index))
        }
    }
}

nonisolated enum OpenSkySaveCallDecoder {
    static func decodeCalls(_ payload: Data) throws -> PapyrusCallSnapshot {
        var reader = SaveReader(payload)
        var snapshot = PapyrusCallSnapshot()
        let arrayCount = try count(
            &reader,
            "PCAL array count",
            OpenSkySaveFormat.minimumCallArraySize
        )
        for _ in 0 ..< arrayCount {
            let elementType = try reader.string("PCAL array element type")
            try snapshot.arrays.append(
                PapyrusSavedArray(elementType: elementType, elements: decodeValues(&reader))
            )
        }
        let callCount = try count(
            &reader,
            "PCAL call count",
            OpenSkySaveFormat.minimumCallEntrySize
        )
        for _ in 0 ..< callCount {
            try snapshot.calls.append(decodeCall(&reader))
        }
        return snapshot
    }

    private static func count(
        _ reader: inout SaveReader, _ context: String, _ minimumSize: Int
    ) throws -> UInt32 {
        let count = try reader.uint32(context)
        try SaveCountCheck.validate(
            count: count,
            minimumElementSize: minimumSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.papyrusCalls
        )
        return count
    }

    private static func decodeCall(_ reader: inout SaveReader) throws -> PapyrusCallState {
        let flags = try reader.uint8("PCAL call flags")
        let owner = flags & CallTag.hasOwner == 0 ? nil : try decodeInstance(&reader)
        let nativeScript = try reader.string("PCAL native script")
        let nativeFunction = try reader.string("PCAL native function")
        let returnType = try reader.string("PCAL return type")
        let wake = try decodeWake(&reader)
        let resume = try decodeReturn(&reader)
        let frameCount = try count(
            &reader, "PCAL frame count", OpenSkySaveFormat.minimumCallFrameSize
        )
        var frames: [PapyrusFrameState] = []
        for _ in 0 ..< frameCount {
            try frames.append(decodeFrame(&reader))
        }
        var call = PapyrusCallState(wake: wake, resume: resume, frames: frames)
        call.owner = owner
        call.holdsInstance = flags & CallTag.holdsInstance != 0
        call.nativeScript = nativeScript
        call.nativeFunction = nativeFunction
        call.returnType = returnType
        return call
    }

    private static func decodeFrame(_ reader: inout SaveReader) throws -> PapyrusFrameState {
        let script = try reader.string("PCAL frame script")
        let ordinal = try reader.uint32("PCAL function ordinal")
        let instructionCount = try reader.uint32("PCAL instruction count")
        let instance = try reader.bool("PCAL frame instance flag") ? decodeInstance(&reader) : nil
        var frame = try PapyrusFrameState(
            script: script, functionOrdinal: Int(ordinal), instructionCount: Int(instructionCount),
            instance: instance, completion: decodeReturn(&reader)
        )
        frame.instructionIndex = try Int(reader.uint32("PCAL instruction index"))
        frame.slots = try decodeValues(&reader)
        return frame
    }

    private static func decodeInstance(_ reader: inout SaveReader) throws -> PapyrusInstanceKey {
        let reference = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        return try PapyrusInstanceKey(
            reference: reference, scriptName: reader.string("PCAL instance script")
        )
    }

    private static func decodeReturn(_ reader: inout SaveReader) throws -> PapyrusSavedReturn {
        let tag = try reader.uint8("PCAL return tag")
        switch tag {
        case CallTag.returnRoot: return .root
        case CallTag.returnDiscard: return .discard
        case CallTag.returnUnread: return .assign(nil)
        case CallTag.returnVariable: return try .assign(reader.string("PCAL return variable"))
        default: throw OpenSkySaveError.invalidValue(context: "PCAL return tag \(tag)")
        }
    }

    private static func decodeWake(_ reader: inout SaveReader) throws -> PapyrusSavedWake {
        let tag = try reader.uint8("PCAL wake tag")
        switch tag {
        case CallTag.wakeRealSeconds:
            let seconds = try duration(reader.uint64("PCAL real seconds"))
            let answer = try reader.bool("PCAL answer flag") ? decodeValue(&reader) : nil
            return .realSeconds(seconds, answer: answer)
        case CallTag.wakeMenuSeconds:
            return try .menuSeconds(duration(reader.uint64("PCAL menu seconds")))
        case CallTag.wakeGameHours:
            return try .gameHours(duration(reader.uint64("PCAL game hours")))
        case CallTag.wakeQuestFragments:
            let quest = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            return try .questFragments(quest: quest, answer: decodeValue(&reader))
        case CallTag.wakeQuestStart:
            let quest = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            return try .questStart(quest: quest, thenFragments: reader.bool("PCAL fragments flag"))
        case CallTag.wakeLost:
            return .lost
        default:
            throw OpenSkySaveError.invalidValue(context: "PCAL wake tag \(tag)")
        }
    }

    /// Non-finite or negative becomes zero, as for `PTMR`: the call goes on at the next step.
    private static func duration(_ bits: UInt64) -> Double {
        let value = Double(bitPattern: bits)
        return value.isFinite && value > 0 ? value : 0
    }

    private static func decodeValues(_ reader: inout SaveReader) throws -> [PapyrusSavedValue] {
        let valueCount = try count(&reader, "PCAL value count", 1)
        var values: [PapyrusSavedValue] = []
        values.reserveCapacity(Int(valueCount))
        for _ in 0 ..< valueCount {
            try values.append(decodeValue(&reader))
        }
        return values
    }

    private static func decodeValue(_ reader: inout SaveReader) throws -> PapyrusSavedValue {
        let tag = try reader.uint8("PCAL value tag")
        switch tag {
        case OpenSkySaveFormat.ValueTag.none:
            return .none
        case OpenSkySaveFormat.ValueTag.boolean:
            return try .boolean(reader.bool("PCAL boolean value"))
        case OpenSkySaveFormat.ValueTag.integer:
            return try .integer(Int32(bitPattern: reader.uint32("PCAL integer value")))
        case OpenSkySaveFormat.ValueTag.float:
            let number = try Float(bitPattern: reader.uint32("PCAL float value"))
            return .float(number.isFinite ? number : 0)
        case OpenSkySaveFormat.ValueTag.string:
            return try .string(reader.string("PCAL string value"))
        case CallTag.scriptInstance:
            return try .instance(decodeInstance(&reader))
        case CallTag.reference:
            return try .reference(OpenSkySaveEntryDecoder.decodeKey(&reader))
        case CallTag.alias:
            let quest = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            return try .alias(quest: quest, id: reader.uint32("PCAL alias ID"))
        case CallTag.array:
            return try .array(Int(reader.uint32("PCAL array index")))
        default:
            throw OpenSkySaveError.invalidValue(context: "PCAL value tag \(tag)")
        }
    }
}
