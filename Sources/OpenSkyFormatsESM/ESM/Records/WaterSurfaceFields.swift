// WATR DNAM fields that shape the water surface. Offsets from xEdit dev-4.1.6
// `wbDefinitionsTES5.pas`; the table is in docs/formats/water.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct WaterSurfaceFields: Equatable, Sendable {
    public let sunSpecularPower: Float
    public let reflectivity: Float
    public let fresnelAmount: Float
    /// Above-water fog near and far planes, in game units of water depth.
    public let fogNear: Float
    public let fogFar: Float
    /// Three noise layers, each in degrees.
    public let windDirections: SIMD3<Float>
    public let windSpeeds: SIMD3<Float>
    /// Game units per noise tile, one per layer.
    public let uvScales: SIMD3<Float>
    public let amplitudes: SIMD3<Float>
    public let reflectionMagnitude: Float
    public let sunSparkleMagnitude: Float
    public let sunSpecularMagnitude: Float
    public let sunSparklePower: Float

    public init(
        sunSpecularPower: Float, reflectivity: Float, fresnelAmount: Float,
        fogNear: Float, fogFar: Float,
        windDirections: SIMD3<Float>, windSpeeds: SIMD3<Float>,
        uvScales: SIMD3<Float>, amplitudes: SIMD3<Float>,
        reflectionMagnitude: Float, sunSparkleMagnitude: Float,
        sunSpecularMagnitude: Float, sunSparklePower: Float
    ) {
        self.sunSpecularPower = sunSpecularPower
        self.reflectivity = reflectivity
        self.fresnelAmount = fresnelAmount
        self.fogNear = fogNear
        self.fogFar = fogFar
        self.windDirections = windDirections
        self.windSpeeds = windSpeeds
        self.uvScales = uvScales
        self.amplitudes = amplitudes
        self.reflectionMagnitude = reflectionMagnitude
        self.sunSparkleMagnitude = sunSparkleMagnitude
        self.sunSpecularMagnitude = sunSpecularMagnitude
        self.sunSparklePower = sunSparklePower
    }

    /// Reads a 228- or 232-byte DNAM; both sizes share these offsets.
    init(dnam: Data) throws {
        var reader = BinaryReader(dnam)
        func float(at offset: Int) throws -> Float {
            reader.seek(to: offset)
            return try reader.readFloat32()
        }
        func float3(at offset: Int) throws -> SIMD3<Float> {
            reader.seek(to: offset)
            return try reader.readFloat3()
        }
        try self.init(
            sunSpecularPower: float(at: 16), reflectivity: float(at: 20),
            fresnelAmount: float(at: 24), fogNear: float(at: 32), fogFar: float(at: 36),
            windDirections: float3(at: 100), windSpeeds: float3(at: 112),
            uvScales: float3(at: 172), amplitudes: float3(at: 184),
            reflectionMagnitude: float(at: 196), sunSparkleMagnitude: float(at: 200),
            sunSpecularMagnitude: float(at: 204), sunSparklePower: float(at: 224)
        )
    }
}
