// IMAD image-space adapter: time envelopes that animate image-space values
// over a duration. DNAM holds a keyframe count per channel; each channel field
// holds (time, value) pairs. Layout and sources: docs/formats/image-spaces.md.

import Foundation
import OpenSkyFormatsCore

/// One animated IMAD value. HDR and cinematic channels come as a multiply and an add envelope.
nonisolated public enum ImageSpaceChannel: Hashable, Sendable {
    case blurRadius
    case doubleVisionStrength
    case radialBlurStrength
    case radialBlurRampUp
    case radialBlurStart
    case radialBlurRampDown
    case radialBlurDownStart
    case depthOfFieldStrength
    case depthOfFieldDistance
    case depthOfFieldRange
    case motionBlurStrength
    /// `\x00IAD` to `\x10IAD` multiply, `@IAD` to `PIAD` add. Index 0 is eye-adapt speed.
    case hdr(index: Int, add: Bool)
    /// `\x11IAD` to `\x14IAD` multiply, `QIAD` to `TIAD` add. Index 0 is saturation.
    case cinematic(index: Int, add: Bool)

    static let named: [FourCC: ImageSpaceChannel] = [
        "BNAM": .blurRadius, "VNAM": .doubleVisionStrength, "RNAM": .radialBlurStrength,
        "SNAM": .radialBlurRampUp, "UNAM": .radialBlurStart, "NAM1": .radialBlurRampDown,
        "NAM2": .radialBlurDownStart, "WNAM": .depthOfFieldStrength,
        "XNAM": .depthOfFieldDistance, "YNAM": .depthOfFieldRange, "NAM4": .motionBlurStrength
    ]

    /// The channel a field signature names, or nil.
    init?(signature: FourCC) {
        if let named = Self.named[signature] {
            self = named
            return
        }
        // The first byte is a counter with 0x40 set for add; the rest spell "IAD".
        guard signature.rawValue >> 8 == FourCC("\0IAD").rawValue >> 8 else { return nil }
        let first = UInt8(truncatingIfNeeded: signature.rawValue)
        let add = first & 0x40 != 0
        let counter = Int(first & 0x3F)
        switch counter {
        case 0 ... 16: self = .hdr(index: counter, add: add)
        case 17 ... 20: self = .cinematic(index: counter - 17, add: add)
        default: return nil
        }
    }
}

nonisolated public struct ImageSpaceKeyframe: Equatable, Sendable {
    public let time: Float
    public let value: Float
}

nonisolated public struct ImageSpaceColorKeyframe: Equatable, Sendable {
    public let time: Float
    public let color: SIMD4<Float>
}

nonisolated public struct ImageSpaceAdapter: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    /// DNAM, 244 bytes.
    public let header: ImageSpaceAdapterHeader?
    public let envelopes: [ImageSpaceChannel: [ImageSpaceKeyframe]]
    /// TNAM.
    public let tint: [ImageSpaceColorKeyframe]
    /// NAM3.
    public let fade: [ImageSpaceColorKeyframe]
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "IMAD")
        formID = fields.formID
        editorID = fields.editorID()
        header = fields.read("DNAM") { try ImageSpaceAdapterHeader(&$0) }
        tint = fields.read("TNAM") { try Self.colorKeyframes(&$0) } ?? []
        fade = fields.read("NAM3") { try Self.colorKeyframes(&$0) } ?? []
        var envelopes: [ImageSpaceChannel: [ImageSpaceKeyframe]] = [:]
        for index in fields.fields.indices where !fields.isUsed(at: index) {
            guard let channel = ImageSpaceChannel(signature: fields.fields[index].type)
            else { continue }
            envelopes[channel] = fields.read(at: index) { try Self.keyframes(&$0) }
        }
        self.envelopes = envelopes
        if let header {
            for mismatch in header.countMismatches(envelopes: envelopes, tint: tint, fade: fade) {
                fields.note(.mismatch("IMAD \(mismatch) keyframe count differs from DNAM"))
            }
        }
        skipped = fields.finish()
    }

    private static func keyframes(_ reader: inout BinaryReader) throws -> [ImageSpaceKeyframe] {
        var frames: [ImageSpaceKeyframe] = []
        while reader.bytesRemaining >= 8 {
            try frames.append(ImageSpaceKeyframe(
                time: reader.readFloat32(),
                value: reader.readFloat32()
            ))
        }
        return frames
    }

    private static func colorKeyframes(_ reader: inout BinaryReader) throws
        -> [ImageSpaceColorKeyframe]
    {
        var frames: [ImageSpaceColorKeyframe] = []
        while reader.bytesRemaining >= 20 {
            let time = try reader.readFloat32()
            let color = try SIMD4(
                reader.readFloat32(),
                reader.readFloat32(),
                reader.readFloat32(),
                reader.readFloat32()
            )
            frames.append(ImageSpaceColorKeyframe(time: time, color: color))
        }
        return frames
    }
}

/// IMAD DNAM: flags, duration, and the keyframe count of every channel.
nonisolated public struct ImageSpaceAdapterHeader: Equatable, Sendable {
    public let isAnimatable: Bool
    public let duration: Float
    /// Keyframe counts per channel, as DNAM declares them.
    public let counts: [ImageSpaceChannel: Int]
    public let tintCount: Int
    public let fadeCount: Int
    public let radialBlurUsesTarget: Bool
    public let radialBlurCenter: SIMD2<Float>
    public let depthOfFieldUsesTarget: Bool
    /// 0x01 front mode, 0x02 back mode, 0x04 no sky.
    public let depthOfFieldFlags: UInt8

    init(_ reader: inout BinaryReader) throws {
        isAnimatable = try reader.readUInt32() != 0
        duration = try reader.readFloat32()
        var counts: [ImageSpaceChannel: Int] = [:]
        for index in 0 ..< 17 {
            counts[.hdr(index: index, add: false)] = try Int(reader.readUInt32())
            counts[.hdr(index: index, add: true)] = try Int(reader.readUInt32())
        }
        for index in 0 ..< 4 {
            counts[.cinematic(index: index, add: false)] = try Int(reader.readUInt32())
            counts[.cinematic(index: index, add: true)] = try Int(reader.readUInt32())
        }
        tintCount = try Int(reader.readUInt32())
        for channel in [
            ImageSpaceChannel.blurRadius,
            .doubleVisionStrength,
            .radialBlurStrength,
            .radialBlurRampUp,
            .radialBlurStart
        ] {
            counts[channel] = try Int(reader.readUInt32())
        }
        radialBlurUsesTarget = try reader.readUInt32() != 0
        radialBlurCenter = try SIMD2(reader.readFloat32(), reader.readFloat32())
        for channel in [
            ImageSpaceChannel.depthOfFieldStrength,
            .depthOfFieldDistance,
            .depthOfFieldRange
        ] {
            counts[channel] = try Int(reader.readUInt32())
        }
        depthOfFieldUsesTarget = try reader.readUInt8() != 0
        depthOfFieldFlags = try reader.readUInt8()
        reader.skip(2)
        counts[.radialBlurRampDown] = try Int(reader.readUInt32())
        counts[.radialBlurDownStart] = try Int(reader.readUInt32())
        fadeCount = try Int(reader.readUInt32())
        counts[.motionBlurStrength] = try Int(reader.readUInt32())
        self.counts = counts
    }

    /// The channels whose keyframe count differs from the declared one.
    func countMismatches(
        envelopes: [ImageSpaceChannel: [ImageSpaceKeyframe]],
        tint: [ImageSpaceColorKeyframe],
        fade: [ImageSpaceColorKeyframe]
    ) -> [String] {
        var mismatches = counts.compactMap { channel, count in
            (envelopes[channel]?.count ?? 0) == count ? nil : "\(channel)"
        }
        if tint.count != tintCount {
            mismatches.append("tint")
        }
        if fade.count != fadeCount {
            mismatches.append("fade")
        }
        return mismatches.sorted()
    }
}
