// EFSH effect shader: the membrane, edge, and particle look of a magic effect.
// DATA grew over form versions, so it is read member by member from a table
// and stops where the bytes end. Every member takes 4 bytes. Layout and sources:
// docs/formats/effect-shaders.md.

import Foundation
import OpenSkyFormatsCore

/// One DATA member, in file order. The names follow xEdit `wbRecord(EFSH, ...)`.
nonisolated public enum EffectShaderMember: String, CaseIterable, Sendable {
    case legacyFlags, membraneSourceBlend, membraneBlendOperation, membraneZTest
    case fillColorKey1, fillAlphaFadeInTime, fillFullAlphaTime, fillAlphaFadeOutTime
    case fillPersistentAlphaRatio, fillAlphaPulseAmplitude, fillAlphaPulseFrequency
    case fillAnimationSpeedU, fillAnimationSpeedV
    case edgeFalloff, edgeColor, edgeAlphaFadeInTime, edgeFullAlphaTime, edgeAlphaFadeOutTime
    case edgePersistentAlphaRatio, edgeAlphaPulseAmplitude, edgeAlphaPulseFrequency
    case fillFullAlphaRatio, edgeFullAlphaRatio, membraneDestBlend
    case particleSourceBlend, particleBlendOperation, particleZTest, particleDestBlend
    case particleBirthRampUpTime, particleFullBirthTime, particleBirthRampDownTime
    case particleFullBirthRatio, particlePersistentCount, particleLifetime
    case particleLifetimeVariance, particleInitialSpeedAlongNormal
    case particleAccelerationAlongNormal, particleInitialVelocity1, particleInitialVelocity2
    case particleInitialVelocity3, particleAcceleration1, particleAcceleration2
    case particleAcceleration3, particleScaleKey1, particleScaleKey2, particleScaleKey1Time
    case particleScaleKey2Time, colorKey1, colorKey2, colorKey3, colorKey1Alpha
    case colorKey2Alpha, colorKey3Alpha, colorKey1Time, colorKey2Time, colorKey3Time
    case particleInitialSpeedVariance, particleInitialRotation, particleInitialRotationVariance
    case particleRotationSpeed, particleRotationSpeedVariance, addonModels
    case holesStartTime, holesEndTime, holesStartValue, holesEndValue, edgeWidth
    case edgeWidthColor, explosionWindSpeed, textureCountU, textureCountV
    case addonFadeInTime, addonFadeOutTime, addonScaleStart, addonScaleEnd
    case addonScaleInTime, addonScaleOutTime, ambientSound, fillColorKey2, fillColorKey3
    case fillColorKey1Scale, fillColorKey2Scale, fillColorKey3Scale
    case fillColorKey1Time, fillColorKey2Time, fillColorKey3Time
    case colorScale, birthPositionOffset, birthPositionOffsetVariance
    case animatedStartFrame, animatedStartFrameVariation, animatedEndFrame
    case animatedLoopStartFrame, animatedLoopStartVariation, animatedFrameCount
    case animatedFrameCountVariation, flags, fillTextureScaleU, fillTextureScaleV
    case sceneGraphEmitDepthLimit

    /// How the member is stored. Members not listed are float32.
    fileprivate var kind: EffectShaderValue.Kind {
        Self.kinds[self] ?? .float
    }

    private static let kinds: [Self: EffectShaderValue.Kind] = {
        var kinds: [Self: EffectShaderValue.Kind] = [
            .legacyFlags: .byteThenPad, .addonModels: .formID, .ambientSound: .formID,
            .textureCountU: .uint32, .textureCountV: .uint32, .flags: .uint32,
            .sceneGraphEmitDepthLimit: .uint16ThenPad
        ]
        let colors: [Self] = [
            .fillColorKey1, .edgeColor, .colorKey1, .colorKey2, .colorKey3, .edgeWidthColor,
            .fillColorKey2, .fillColorKey3
        ]
        let words: [Self] = [
            .membraneSourceBlend, .membraneBlendOperation, .membraneZTest, .membraneDestBlend,
            .particleSourceBlend, .particleBlendOperation, .particleZTest, .particleDestBlend,
            .animatedStartFrame, .animatedStartFrameVariation, .animatedEndFrame,
            .animatedLoopStartFrame, .animatedLoopStartVariation, .animatedFrameCount,
            .animatedFrameCountVariation
        ]
        for member in colors {
            kinds[member] = .color
        }
        for member in words {
            kinds[member] = .uint32
        }
        return kinds
    }()
}

nonisolated public enum EffectShaderValue: Equatable, Sendable {
    case float(Float)
    case uint(UInt32)
    case color(SIMD4<UInt8>)
    case formID(FormID)

    fileprivate enum Kind {
        case float, uint32, color, formID, byteThenPad, uint16ThenPad
    }

    fileprivate init(kind: Kind, reader: inout BinaryReader) throws {
        switch kind {
        case .float: self = try .float(reader.readFloat32())
        case .uint32: self = try .uint(reader.readUInt32())
        case .formID: self = try .formID(reader.readFormID())
        case .color:
            self = try .color(SIMD4(
                reader.readUInt8(),
                reader.readUInt8(),
                reader.readUInt8(),
                reader.readUInt8()
            ))
        case .byteThenPad:
            self = try .uint(UInt32(reader.readUInt8()))
            reader.skip(3)
        case .uint16ThenPad:
            self = try .uint(UInt32(reader.readUInt16()))
            reader.skip(2)
        }
    }
}

nonisolated public struct EffectShader: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    /// ICON.
    public let fillTexture: String?
    /// ICO2.
    public let particleTexture: String?
    /// NAM7.
    public let holesTexture: String?
    /// NAM8.
    public let membranePaletteTexture: String?
    /// NAM9.
    public let particlePaletteTexture: String?
    /// The DATA members present, in file order.
    public let members: [(member: EffectShaderMember, value: EffectShaderValue)]
    /// The DATA size, for the size histogram.
    public let dataSize: Int?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "EFSH")
        formID = fields.formID
        editorID = fields.editorID()
        fillTexture = fields.zstring("ICON")
        particleTexture = fields.zstring("ICO2")
        holesTexture = fields.zstring("NAM7")
        membranePaletteTexture = fields.zstring("NAM8")
        particlePaletteTexture = fields.zstring("NAM9")
        dataSize = fields.fields.first { $0.type == "DATA" }?.data.count
        let members = fields.read("DATA") { try Self.members(&$0) }
        self.members = members ?? []
        if let dataSize, dataSize % 4 != 0 {
            fields.note(.mismatch("EFSH DATA size is not a multiple of 4"))
        }
        skipped = fields.finish()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.formID == rhs.formID && lhs.dataSize == rhs.dataSize
            && lhs.members
            .elementsEqual(rhs.members) { $0.member == $1.member && $0.value == $1.value }
    }

    public func value(_ member: EffectShaderMember) -> EffectShaderValue? {
        members.first { $0.member == member }?.value
    }

    /// The uint32 flags: 0x01 no membrane, 0x08 no particles, 0x20 skin only,
    /// 0x8000 animated particles, 0x01000000 blood geometry. Nil when DATA is too short.
    public var flags: UInt32? {
        guard case let .uint(value) = value(.flags) else { return nil }
        return value
    }

    private static func members(
        _ reader: inout BinaryReader
    ) throws -> [(member: EffectShaderMember, value: EffectShaderValue)] {
        var members: [(member: EffectShaderMember, value: EffectShaderValue)] = []
        for member in EffectShaderMember.allCases where reader.bytesRemaining >= 4 {
            try members.append((member, EffectShaderValue(kind: member.kind, reader: &reader)))
        }
        return members
    }
}
