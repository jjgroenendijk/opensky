// SCRS chunk: flags, values, and form links scripts set on a form, and the forms a
// script added to a list. Layout: docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// Names in sorted order, so the same state writes the same bytes.
    public static func writeScriptedStates(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        writeStory(
            ScriptedReferenceState.self, tag: OpenSkySaveFormat.ChunkTag.scriptedStates,
            entries, &writer
        ) { state, payload in
            payload.writeUInt32(UInt32(clamping: state.flags.count))
            for (name, flag) in state.flags.sorted(by: { $0.key < $1.key }) {
                writeString(name, into: &payload)
                payload.writeUInt8(flag ? 1 : 0)
            }
            payload.writeUInt32(UInt32(clamping: state.values.count))
            for (name, value) in state.values.sorted(by: { $0.key < $1.key }) {
                writeString(name, into: &payload)
                payload.writeFloat32(value)
            }
            payload.writeUInt32(UInt32(clamping: state.forms.count))
            for (name, form) in state.forms.sorted(by: { $0.key < $1.key }) {
                writeString(name, into: &payload)
                writeKey(form, into: &payload)
            }
            payload.writeUInt32(UInt32(clamping: state.addedForms.count))
            for form in state.addedForms {
                writeKey(form, into: &payload)
            }
        }
    }
}

nonisolated extension OpenSkySaveStoryDecoder {
    public static func decodeScriptedStates(
        _ payload: Data
    ) throws -> [SaveStoryEntry<ScriptedReferenceState>] {
        let tag = OpenSkySaveFormat.ChunkTag.scriptedStates
        return try decode(
            payload, tag: tag, minimumSize: OpenSkySaveFormat.minimumScriptedStateEntrySize
        ) { reader in
            var flags: [String: Bool] = [:]
            for _ in try 0 ..< count(&reader, "SCRS flag count", tag: tag) {
                let name = try reader.string("SCRS flag name")
                flags[name] = try reader.bool("SCRS flag")
            }
            var values: [String: Float] = [:]
            for _ in try 0 ..< count(&reader, "SCRS value count", tag: tag) {
                let name = try reader.string("SCRS value name")
                values[name] = try reader.float32("SCRS value")
            }
            var forms: [String: ReferenceKey] = [:]
            for _ in try 0 ..< count(&reader, "SCRS form count", tag: tag) {
                let name = try reader.string("SCRS form name")
                forms[name] = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            }
            var added: [ReferenceKey] = []
            for _ in try 0 ..< count(&reader, "SCRS added form count", tag: tag) {
                try added.append(OpenSkySaveEntryDecoder.decodeKey(&reader))
            }
            return ScriptedReferenceState(
                flags: flags, values: values, forms: forms, addedForms: added
            )
        }
    }

    /// A count whose elements need at least two bytes each, checked against the rest.
    private static func count(
        _ reader: inout SaveReader, _ context: String, tag: String
    ) throws -> UInt32 {
        let count = try reader.uint32(context)
        try OpenSkySaveDecoder.validate(
            count: count, minimumElementSize: 2, remaining: reader.bytesRemaining, chunk: tag
        )
        return count
    }
}
