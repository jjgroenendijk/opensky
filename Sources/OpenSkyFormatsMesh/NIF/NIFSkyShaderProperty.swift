// `BSSkyShaderProperty`: the material of a sky mesh, such as the cloud dome,
// the stars, or a moon. Layout: docs/formats/nif-materials.md#sky-shader.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct NIFSkyShaderProperty: Equatable, Sendable {
    public static let typeName = "BSSkyShaderProperty"

    /// nif.xml `SkyObjectType`: what part of the sky the shape is.
    public enum SkyObject: UInt32, Equatable, Sendable {
        case texture = 0
        case sunGlare = 1
        case sky = 2
        case clouds = 3
        case stars = 5
        case moonStarsMask = 7
    }

    public let name: String?
    public let shaderFlags1: UInt32
    public let shaderFlags2: UInt32
    public let uvOffset: SIMD2<Float>
    public let uvScale: SIMD2<Float>
    /// The texture path as the file names it, under `textures\`.
    public let sourceTexture: String
    /// Nil for a value nif.xml does not name.
    public let skyObject: SkyObject?

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        let net = try NIFObjectNET(reader: &reader, header: header)
        name = net.name
        shaderFlags1 = try reader.readUInt32()
        shaderFlags2 = try reader.readUInt32()
        uvOffset = try SIMD2(reader.readFloat32(), reader.readFloat32())
        uvScale = try SIMD2(reader.readFloat32(), reader.readFloat32())
        sourceTexture = try reader.readNIFSizedString()
        skyObject = try SkyObject(rawValue: reader.readUInt32())
    }

    public var sourceTexturePath: String? {
        sourceTexture.isEmpty ? nil : NIFShaderTextureSet.vfsKey(for: sourceTexture)
    }

    /// Sky meshes are drawn unlit, coloured by their texture and vertex colours.
    public var material: Material {
        let fallback = Material.fallback
        return Material(
            diffuseTexture: sourceTexturePath,
            normalTexture: nil,
            uvOffset: uvOffset,
            uvScale: uvScale,
            alpha: fallback.alpha,
            glossiness: fallback.glossiness,
            specularColor: fallback.specularColor,
            specularStrength: 0,
            doubleSided: true,
            alphaBlend: skyObject != .sky,
            alphaTestThreshold: nil,
            effect: EffectShading(
                baseColor: SIMD4(repeating: 1), baseColorScale: 1, paletteTexture: nil,
                paletteColor: false, paletteAlpha: false, falloff: nil,
                vertexColors: true, vertexAlpha: true
            )
        )
    }
}

nonisolated extension NIFBlockDecoders {
    static let shaders: [String: Decode] = [
        NIFSkyShaderProperty.typeName: { try NIFSkyShaderProperty(reader: &$0, header: $1) }
    ]
}
