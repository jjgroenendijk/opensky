// The ModelBase fields that no runtime reads yet: bounds, the model group,
// destruction, marker colors, flags, furniture markers, door teleports, and
// tree animation data. Layout and sources: docs/formats/world-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ModelBaseDetails: Equatable, Sendable {
    /// FURN ENAM, NAM0, and FNMK: one furniture marker.
    public struct FurnitureMarker: Equatable, Sendable {
        public var index: UInt32?
        /// NAM0 disabled entry points: 0x01 front, 0x02 behind, 0x04 right, 0x08 left, 0x10 up.
        public var disabledEntryPoints: UInt16?
        public var keyword: FormID?
    }

    /// FURN FNPR.
    public struct MarkerEntryPoints: Equatable, Sendable {
        /// 0 none, 1 sit, 2 lay, 4 lean.
        public let type: UInt16
        public let entryPoints: UInt16
    }

    /// TREE CNAM: wind animation values.
    public struct TreeData: Equatable, Sendable {
        public let trunkFlexibility: Float
        public let branchFlexibility: Float
        public let trunkAmplitude: Float
        public let frontAmplitude: Float
        public let backAmplitude: Float
        public let sideAmplitude: Float
        public let frontFrequency: Float
        public let backFrequency: Float
        public let sideFrequency: Float
        public let leafFlexibility: Float
        public let leafAmplitude: Float
        public let leafFrequency: Float
    }

    public var bounds: ObjectBounds?
    public var model: ModelData?
    public var destructible: Destructible?
    /// PNAM on ACTI, FURN, and FLOR. TACT PNAM has the same 4 bytes, unnamed by xEdit.
    public var markerColor: SIMD4<UInt8>?
    /// FNAM on ACTI, FURN, FLOR, and TACT. DOOR FNAM is one byte and read by ModelBase.
    public var flags: UInt16?
    /// ACTI WNAM, a WATR.
    public var waterType: FormID?
    /// FURN NAM1, a SPEL.
    public var associatedSpell: FormID?
    public var furnitureMarkers: [FurnitureMarker] = []
    public var markerEntryPoints: [MarkerEntryPoints] = []
    /// FURN XMRK, the marker model.
    public var markerModelPath: String?
    /// DOOR TNAM: random teleport destinations, each a CELL or WRLD.
    public var randomTeleports: [FormID] = []
    public var treeData: TreeData?
    /// MSTT DATA: 0x01 on local map, 0x02 unknown, 0x04 static.
    public var movableStaticFlags: UInt8?

    /// Reads the details from the fields ModelBase left unused.
    static func decode(_ fields: inout RecordFields) -> Self {
        var details = Self()
        details.bounds = fields.bounds()
        details.model = fields.model()
        details.destructible = fields.destructible()
        let type = fields.recordType
        if ["ACTI", "FURN", "FLOR", "TACT"].contains(type) {
            details.markerColor = fields.read("PNAM") {
                try SIMD4($0.readUInt8(), $0.readUInt8(), $0.readUInt8(), $0.readUInt8())
            }
            details.flags = fields.uint16("FNAM")
        }
        switch type {
        case "ACTI": details.waterType = fields.formID("WNAM")
        case "DOOR": details.randomTeleports = fields.formIDs("TNAM")
        case "TREE": details.treeData = fields.read("CNAM") { try TreeData(&$0) }
        case "MSTT": details.movableStaticFlags = fields.uint8("DATA")
        case "FURN": details.readFurniture(&fields)
        default: break
        }
        return details
    }

    private mutating func readFurniture(_ fields: inout RecordFields) {
        associatedSpell = fields.formID("NAM1")
        markerEntryPoints = fields.readAll("FNPR") {
            try MarkerEntryPoints(type: $0.readUInt16(), entryPoints: $0.readUInt16())
        }
        markerModelPath = fields.zstring("XMRK")
        furnitureMarkers = Self.furnitureMarkers(&fields)
    }

    private static func furnitureMarkers(_ fields: inout RecordFields) -> [FurnitureMarker] {
        var markers: [FurnitureMarker] = []
        for index in fields.fields.indices where !fields.isUsed(at: index) {
            let type = fields.fields[index].type
            guard type == "ENAM" || type == "NAM0" || type == "FNMK" else { continue }
            if type == "ENAM" || markers.isEmpty {
                markers.append(FurnitureMarker())
            }
            let last = markers.count - 1
            switch type {
            case "ENAM": markers[last].index = fields.read(at: index) { try $0.readUInt32() }
            case "NAM0":
                markers[last].disabledEntryPoints = fields.read(at: index) {
                    _ = try $0.read(count: 2)
                    return try $0.readUInt16()
                }
            default: markers[last].keyword = fields.read(at: index) { try $0.readFormID() }?.nonNull
            }
        }
        return markers
    }
}

nonisolated extension ModelBaseDetails.TreeData {
    init(_ reader: inout BinaryReader) throws {
        trunkFlexibility = try reader.readFloat32()
        branchFlexibility = try reader.readFloat32()
        trunkAmplitude = try reader.readFloat32()
        frontAmplitude = try reader.readFloat32()
        backAmplitude = try reader.readFloat32()
        sideAmplitude = try reader.readFloat32()
        frontFrequency = try reader.readFloat32()
        backFrequency = try reader.readFloat32()
        sideFrequency = try reader.readFloat32()
        leafFlexibility = try reader.readFloat32()
        leafAmplitude = try reader.readFloat32()
        leafFrequency = try reader.readFloat32()
    }
}
