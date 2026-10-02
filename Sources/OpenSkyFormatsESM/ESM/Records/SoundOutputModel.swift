// SOPM sound output model and REVB reverb parameters: how a sound reaches the
// speakers and how a room colors it. Layout and sources:
// docs/formats/sound-output-reverb.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct SoundOutputModel: Equatable, Sendable {
    /// ANAM, 20 bytes.
    public struct Attenuation: Equatable, Sendable {
        public let minimumDistance: Float
        public let maximumDistance: Float
        /// Five curve points, each 0 to 100.
        public let curve: [UInt8]
    }

    public let formID: FormID
    public let editorID: String?
    /// NAM1 byte 0: 0x01 attenuates with distance, 0x02 allows rumble.
    public let flags: UInt8?
    /// NAM1 byte 3.
    public let reverbSendPercent: UInt8?
    /// MNAM: 0 uses HRTF, 1 defined speaker output.
    public let type: UInt32?
    /// ONAM: per input channel (mono, stereo left, stereo right) the level for
    /// each of 8 speakers (L, R, C, LFE, RL, RR, BL, BR).
    public let channelMatrix: [[UInt8]]
    public let attenuation: Attenuation?
    /// FNAM, CNAM, SNAM: leftovers xEdit marks unused, kept raw.
    public let leftovers: [FourCC: Data]
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "SOPM")
        formID = fields.formID
        editorID = fields.editorID()
        let data = fields.read("NAM1") { reader -> (UInt8, UInt8) in
            let flags = try reader.readUInt8()
            reader.skip(2)
            return try (flags, reader.readUInt8())
        }
        flags = data?.0
        reverbSendPercent = data?.1
        type = fields.uint32("MNAM")
        channelMatrix = fields.read("ONAM") { reader in
            try (0 ..< 3).map { _ in try (0 ..< 8).map { _ in try reader.readUInt8() } }
        } ?? []
        attenuation = fields.read("ANAM") { reader in
            reader.skip(4)
            let minimum = try reader.readFloat32()
            let maximum = try reader.readFloat32()
            let curve = try (0 ..< 5).map { _ in try reader.readUInt8() }
            return Attenuation(minimumDistance: minimum, maximumDistance: maximum, curve: curve)
        }
        var leftovers: [FourCC: Data] = [:]
        for type: FourCC in ["FNAM", "CNAM", "SNAM"] {
            leftovers[type] = fields.bytes(type)
        }
        self.leftovers = leftovers
        skipped = fields.finish()
    }
}

nonisolated public struct ReverbParameters: Equatable, Sendable {
    /// DATA, 14 bytes.
    public struct Properties: Equatable, Sendable {
        public let decayTimeMilliseconds: UInt16
        public let hfReferenceHertz: UInt16
        public let roomFilter: Int8
        public let roomHFFilter: Int8
        public let reflections: Int8
        public let reverbAmplitude: Int8
        /// Stored as hundredths.
        public let decayHFRatio: Float
        /// Scaled; xEdit gives no unit conversion.
        public let reflectDelay: UInt8
        public let reverbDelayMilliseconds: UInt8
        public let diffusionPercent: UInt8
        public let densityPercent: UInt8
        public let unknown: UInt8
    }

    public let formID: FormID
    public let editorID: String?
    public let properties: Properties?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "REVB")
        formID = fields.formID
        editorID = fields.editorID()
        properties = fields.read("DATA") { reader in
            try Properties(
                decayTimeMilliseconds: reader.readUInt16(), hfReferenceHertz: reader.readUInt16(),
                roomFilter: reader.readInt8(), roomHFFilter: reader.readInt8(),
                reflections: reader.readInt8(), reverbAmplitude: reader.readInt8(),
                decayHFRatio: Float(reader.readUInt8()) / 100, reflectDelay: reader.readUInt8(),
                reverbDelayMilliseconds: reader.readUInt8(), diffusionPercent: reader.readUInt8(),
                densityPercent: reader.readUInt8(), unknown: reader.readUInt8()
            )
        }
        skipped = fields.finish()
    }
}
