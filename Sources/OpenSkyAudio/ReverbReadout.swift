// The text of the World > Audio reverb readout, kept out of the panel so a
// unit test can pin it.

import Foundation
import OpenSkyFormatsESM

nonisolated public enum ReverbReadout {
    public static func text(record: ReverbParameters?, ramp: ReverbRamp) -> String {
        let target = ramp.target
        let room = target.room.map(\.rawValue) ?? "off"
        let override = ramp.wetOverride.map { ", override \(decibels($0))" } ?? ""
        let playing = ramp.room?.rawValue ?? "off"
        return [
            "Record: \(recordLine(record))",
            "Maps to: \(room), wet \(target.isOff ? "off" : decibels(target.level))",
            "Playing: \(playing), wet \(decibels(ramp.appliedLevel))\(override)"
        ].joined(separator: "\n")
    }

    static func recordLine(_ record: ReverbParameters?) -> String {
        guard let record else { return "none" }
        let name = record.editorID ?? "\(record.formID)"
        guard let data = record.properties else { return "\(name), no data" }
        return "\(name), decay \(data.decayTimeMilliseconds) ms, room \(data.roomFilter) dB,"
            + " reverb \(data.reverbAmplitude) dB"
    }

    static func decibels(_ value: Float) -> String {
        String(format: "%.1f dB", value)
    }
}
