// CELL fields outside the lighting, water and ownership core: links to an
// image space, lock list and sky region, water extras, and raw height and
// occlusion data. Layout and sources: docs/formats/world-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct CellExtras: Equatable, Sendable {
    nonisolated public struct WaterVelocity: Equatable, Sendable {
        public let velocity: SIMD3<Float>
        public let unknown: Float
    }

    /// XCIM, an IMGS.
    public var imageSpace: FormID?
    /// XILL, a FLST or NPC_ whose members may use the cell's locks.
    public var lockList: FormID?
    /// XCCM, a REGN whose sky and weather the interior shows.
    public var skyRegion: FormID?
    /// XNAM.
    public var waterNoiseTexture: String?
    /// XWEM.
    public var waterEnvironmentMap: String?
    /// XWCN or XWCS, the declared XWCU count.
    public var waterVelocityCount: UInt32?
    /// XWCU.
    public var waterVelocities: [WaterVelocity] = []
    /// MHDT: a float offset, then 32x32 uint8 heights. Kept raw.
    public var maxHeightData: Data?
    /// TVDT occlusion data. xEdit leaves it unnamed.
    public var occlusionData: Data?
    /// LNAM, leftover flags that now live in XCLC.
    public var legacyFlags: Data?

    public init() {}

    /// Decodes a field this struct owns. Returns false for any other field.
    mutating func decode(field: ESMField) throws -> Bool {
        var reader = BinaryReader(field.data)
        switch field.type {
        case "XCIM": imageSpace = try reader.readFormID().nonNull
        case "XILL": lockList = try reader.readFormID().nonNull
        case "XCCM": skyRegion = try reader.readFormID().nonNull
        case "XNAM": waterNoiseTexture = try reader.readZString()
        case "XWEM": waterEnvironmentMap = try reader.readZString()
        case "XWCN", "XWCS": waterVelocityCount = try reader.readUInt32()
        case "XWCU":
            while reader.bytesRemaining >= 16 {
                let velocity = try reader.readFloat3()
                try waterVelocities.append(WaterVelocity(
                    velocity: velocity,
                    unknown: reader.readFloat32()
                ))
            }
        case "MHDT": maxHeightData = field.data
        case "TVDT": occlusionData = field.data
        case "LNAM": legacyFlags = field.data
        default: return false
        }
        return true
    }
}
