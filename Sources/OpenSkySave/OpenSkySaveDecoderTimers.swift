// PTMR chunk decoding: pending Papyrus update-timer slots. Shaped like the PSCR decoder:
// the payload is its own `Data`, and the count passes `OpenSkySaveDecoder.validate`.

import Foundation
import OpenSkyScriptingInterface

nonisolated public enum OpenSkySaveTimerDecoder: Sendable {
    /// `PTMR` chunk: a timer count, then one entry per armed slot.
    public static func decodeTimers(_ payload: Data) throws -> [PapyrusTimerState] {
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

    /// A timer duration as a `Float64` bit pattern. Non-finite or negative becomes zero,
    /// as for `PSCR` floats and as the registry itself clamps, so the timer fires on the
    /// next step.
    private static func duration(_ bits: UInt64) -> Double {
        let value = Double(bitPattern: bits)
        return value.isFinite && value > 0 ? value : 0
    }
}
