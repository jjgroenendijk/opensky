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
    public let sunSpecularMagnitude: Float
    public let sunSparklePower: Float
    /// The fields below default to calm values for a record built in code.
    public internal(set) var sunSparkleMagnitude: Float = 0
    public internal(set) var refractionMagnitude: Float = 0
    public internal(set) var noiseFalloff: Float = 0
    public internal(set) var displacement = WaterDisplacementFields()
    /// Under-water fog: amount, then near and far planes in game units.
    public internal(set) var underwaterFogAmount: Float = 0
    public internal(set) var underwaterFogNear: Float = 0
    public internal(set) var underwaterFogFar: Float = 0
    public internal(set) var aboveWaterFogAmount: Float = 0
    /// How finely a river's flow noise repeats; 0 in the 228-byte size.
    public internal(set) var flowMapScale: Float = 0

    public init(
        sunSpecularPower: Float, reflectivity: Float, fresnelAmount: Float,
        fogNear: Float, fogFar: Float,
        windDirections: SIMD3<Float>, windSpeeds: SIMD3<Float>,
        uvScales: SIMD3<Float>, amplitudes: SIMD3<Float>,
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
            sunSpecularMagnitude: float(at: 204), sunSparklePower: float(at: 224)
        )
        sunSparkleMagnitude = try float(at: 200)
        refractionMagnitude = try float(at: 152)
        noiseFalloff = try float(at: 96)
        displacement = try WaterDisplacementFields(
            startingSize: float(at: 72), force: float(at: 76), velocity: float(at: 80),
            falloff: float(at: 84), dampener: float(at: 88)
        )
        aboveWaterFogAmount = try float(at: 132)
        underwaterFogAmount = try float(at: 140)
        underwaterFogNear = try float(at: 144)
        underwaterFogFar = try float(at: 148)
        if dnam.count >= 232 {
            flowMapScale = try float(at: 228)
        }
    }
}

/// `DNAM` displacement simulator: the rings a body in the water sends out.
nonisolated public struct WaterDisplacementFields: Equatable, Sendable {
    public var startingSize: Float = 0
    public var force: Float = 0
    public var velocity: Float = 0
    public var falloff: Float = 0
    public var dampener: Float = 0

    public init() {}

    public init(
        startingSize: Float,
        force: Float,
        velocity: Float,
        falloff: Float,
        dampener: Float
    ) {
        self.startingSize = startingSize
        self.force = force
        self.velocity = velocity
        self.falloff = falloff
        self.dampener = dampener
    }
}
