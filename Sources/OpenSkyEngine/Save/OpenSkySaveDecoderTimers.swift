// PTMR chunk decoding for the OpenSky native save container (issue #277):
// pending Papyrus update-timer slots.
//
// Shaped exactly like the `PSCR` decoder next door. The payload arrives as its
// own `Data`, so the chunk's declared length bounds every read and a corrupt
// count inside the chunk can never walk into the next chunk's bytes, and the
// declared entry count goes through
// `OpenSkySaveDecoder.validate(count:minimumElementSize:remaining:chunk:)`
// before anything reserves storage.

import Foundation

nonisolated enum OpenSkySaveTimerDecoder {
    /// `PTMR` chunk: a timer count, then one entry per armed slot.
    static func decodeTimers(_ payload: Data) throws -> [PapyrusTimerState] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("PTMR timer count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumTimerEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.papyrusTimers
        )
        var states: [PapyrusTimerState] = []
        states.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try states.append(decodeTimer(&reader))
        }
        return states
    }

    private static func decodeTimer(
        _ reader: inout SaveReader
    ) throws -> PapyrusTimerState {
        let reference = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let scriptName = try reader.string("PTMR script name")
        let slotByte = try reader.uint8("PTMR slot")
        guard let slot = PapyrusUpdateTimerSlot(rawValue: Int(slotByte)) else {
            throw OpenSkySaveError.invalidValue(context: "PTMR slot \(slotByte)")
        }
        let interval = try duration(reader.uint64("PTMR interval"))
        let remaining = try duration(reader.uint64("PTMR remaining"))
        return PapyrusTimerState(
            key: PapyrusInstanceKey(reference: reference, scriptName: scriptName),
            slot: slot,
            interval: interval,
            remaining: remaining
        )
    }

    /// A timer duration in the slot's unit, read as a `Float64` bit pattern.
    ///
    /// Non-finite and negative policy, matching the `PSCR` float rule rather
    /// than the `CLOK` one: the value is **normalized to zero**, not rejected.
    /// A script can hand the registry any float it likes, and refusing to load
    /// a whole world because one timer drifted out of range would be the worse
    /// failure. Zero is also what the registry itself clamps such an interval
    /// to, so a normalized timer simply fires on the next fixed step. The
    /// registry re-clamps on restore anyway; normalizing here keeps the decoded
    /// value honest for anything that only inspects the file.
    private static func duration(_ bits: UInt64) -> Double {
        let value = Double(bitPattern: bits)
        return value.isFinite && value > 0 ? value : 0
    }
}
