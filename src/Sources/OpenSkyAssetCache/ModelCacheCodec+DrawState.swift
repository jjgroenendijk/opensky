// The draw state of a cached material: its seven flags, in field order.

import OpenSkyFormatsCore

nonisolated extension ModelCacheCodec {
    static func encode(_ state: MaterialDrawState, into out: inout CachePayloadWriter) {
        for flag in [
            state.depthTest, state.depthWrite, state.decal, state.castsShadows,
            state.receivesShadows, state.distantLOD, state.screenDoor
        ] {
            out.bool(flag)
        }
    }

    static func drawState(_ input: inout CachePayloadReader) throws -> MaterialDrawState {
        var state = MaterialDrawState()
        state.depthTest = try input.bool()
        state.depthWrite = try input.bool()
        state.decal = try input.bool()
        state.castsShadows = try input.bool()
        state.receivesShadows = try input.bool()
        state.distantLOD = try input.bool()
        state.screenDoor = try input.bool()
        return state
    }
}
