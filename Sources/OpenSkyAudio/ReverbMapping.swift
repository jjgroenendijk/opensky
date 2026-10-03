// Maps a `REVB` record onto the environment node's reverb: the nearest factory
// room by decay time, and a wet level from the room and reverb gains. Apple's
// reverb has no decay or delay controls, so a preset stands in for them.
// See docs/formats/sound-output-reverb.md, section "Reverb".

import AVFAudio
import Foundation
import OpenSkyFormatsESM

/// The factory rooms the mapping picks from, smallest first.
nonisolated public enum ReverbRoom: String, Equatable, Sendable, CaseIterable {
    case smallRoom, mediumRoom, largeRoom, mediumHall, largeHall, cathedral

    /// The shortest decay, in milliseconds, each room stands for.
    public var decayFloor: UInt16 {
        switch self {
        case .smallRoom: 0
        case .mediumRoom: 400
        case .largeRoom: 1000
        case .mediumHall: 2000
        case .largeHall: 3000
        case .cathedral: 3500
        }
    }

    public var preset: AVAudioUnitReverbPreset {
        switch self {
        case .smallRoom: .smallRoom
        case .mediumRoom: .mediumRoom
        case .largeRoom: .largeRoom
        case .mediumHall: .mediumHall
        case .largeHall: .largeHall
        case .cathedral: .cathedral
        }
    }

    /// The largest room whose floor the decay reaches.
    public static func nearest(decayMilliseconds: UInt16) -> ReverbRoom {
        allCases.last { decayMilliseconds >= $0.decayFloor } ?? .smallRoom
    }
}

nonisolated public struct ReverbSetting: Equatable, Sendable {
    /// The wet level the environment node allows, in dB.
    public static let levelRange: ClosedRange<Float> = -40 ... 40
    /// A gain at or below this many dB means the record switches reverb off.
    public static let silentGain: Int8 = -60
    public static let off = ReverbSetting(room: nil, level: levelRange.lowerBound, source: nil)

    /// Nil when the reverb is off.
    public let room: ReverbRoom?
    /// The wet level in dB.
    public let level: Float
    /// The record's editor ID, nil when off.
    public let source: String?

    public init(room: ReverbRoom?, level: Float, source: String?) {
        self.room = room
        self.level = min(max(level.isFinite ? level : -40, Self.levelRange.lowerBound), 40)
        self.source = source
    }

    /// Off for a missing record, a zero decay, or a silent room or reverb gain.
    public init(record: ReverbParameters?) {
        guard
            let record, let data = record.properties,
            data.decayTimeMilliseconds > 0,
            data.roomFilter > Self.silentGain, data.reverbAmplitude > Self.silentGain
        else {
            self = .off
            return
        }
        self.init(
            room: .nearest(decayMilliseconds: data.decayTimeMilliseconds),
            level: Float(data.roomFilter) + Float(data.reverbAmplitude),
            source: record.editorID ?? "\(record.formID)"
        )
    }

    public var isOff: Bool {
        room == nil
    }
}
