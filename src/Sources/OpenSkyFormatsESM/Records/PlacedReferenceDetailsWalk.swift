// The field walk behind `PlacedReferenceDetails`. Patrol and room fields are
// groups, so the walk keeps file order. Sources: docs/formats/placed-references.md.

import Foundation
import OpenSkyFormatsCore

nonisolated extension PlacedReferenceDetails {
    static let linkSignatures: Set<FourCC> = [
        "XTNM", "XMBR", "XSPC", "XLIB", "XLCN", "XEZN", "XLRL", "XATR", "XHOR", "XMRC", "XOWN",
        "XEMI"
    ]

    /// xEdit marks these unused; they are leftovers of an older script format.
    static let unusedScriptFields: Set<FourCC> = ["SCHR", "SCTX", "SCDA", "QNAM", "SCRO"]

    /// Decodes the fields a REFR or ACHR decode left. The tally holds what is still unknown.
    static func decode(_ fields: [ESMField]) -> (Self, FieldTally) {
        var details = Self()
        var tally = FieldTally()
        for field in fields {
            do {
                if try !details.decode(field) {
                    tally.note(.unknownField(field.type))
                }
            } catch {
                tally.note(.malformedField(field.type))
            }
        }
        return (details, tally)
    }

    private mutating func decode(_ field: ESMField) throws -> Bool {
        var reader = BinaryReader(field.data)
        if Self.linkSignatures.contains(field.type) {
            if let link = try reader.readFormID().nonNull {
                links[field.type.description] = link
            }
            return true
        }
        if Self.unusedScriptFields.contains(field.type) {
            return true
        }
        if try decodePatrol(field, &reader) || decodeRoom(field, &reader) {
            return true
        }
        if try decodeWater(field, &reader) || decodeScalar(field, &reader) {
            return true
        }
        return try decodeStructure(field, &reader)
    }

    private mutating func decodePatrol(
        _ field: ESMField,
        _ reader: inout BinaryReader
    ) throws -> Bool {
        switch field.type {
        case "XPRD":
            try patrols.append(Patrol(idleTime: reader.readFloat32()))
        case "XPPA" where !patrols.isEmpty:
            patrols[patrols.count - 1].hasScriptMarker = true
        case "INAM" where !patrols.isEmpty:
            patrols[patrols.count - 1].idle = try reader.readFormID().nonNull
        case "TNAM" where !patrols.isEmpty:
            patrols[patrols.count - 1].topic = try reader.readFormID().nonNull
        case "PDTO" where !patrols.isEmpty:
            let type = try reader.readUInt32()
            let topic = type == 0 ? try reader.readFormID().nonNull : nil
            let subtype = type == 0 ? nil : try String(
                bytes: reader.read(count: 4),
                encoding: .ascii
            )
            patrols[patrols.count - 1].topics.append(
                PatrolTopic(type: type, topic: topic, subtype: subtype)
            )
        default:
            return false
        }
        return true
    }

    private mutating func decodeRoom(
        _ field: ESMField,
        _ reader: inout BinaryReader
    ) throws -> Bool {
        switch field.type {
        case "XRMR":
            var header = room ?? Room()
            header.linkedRoomCount = try reader.readUInt8()
            header.flags = try reader.readUInt8()
            room = header
        case "LNAM":
            var header = room ?? Room()
            header.lightingTemplate = try reader.readFormID().nonNull
            room = header
        case "INAM":
            var header = room ?? Room()
            header.imageSpace = try reader.readFormID().nonNull
            room = header
        case "XLRM":
            var header = room ?? Room()
            try header.linkedRooms.append(reader.readFormID())
            room = header
        case "XPOD":
            while reader.bytesRemaining >= 8 {
                try portals.append(Portal(
                    origin: reader.readFormID().nonNull,
                    destination: reader.readFormID().nonNull
                ))
            }
        case "XMBP":
            isMultiBoundPrimitive = true
        default:
            return false
        }
        return true
    }

    private mutating func decodeWater(
        _ field: ESMField,
        _ reader: inout BinaryReader
    ) throws -> Bool {
        switch field.type {
        case "XWCN", "XWCS": waterVelocityCount = try reader.readUInt32()
        case "XWCU":
            while reader.bytesRemaining >= 16 {
                let velocity = try reader.readFloat3()
                try waterVelocities.append(CellExtras.WaterVelocity(
                    velocity: velocity,
                    unknown: reader.readFloat32()
                ))
            }
        case "XCVL": waterLinearVelocity = try reader.readFloat3()
        case "XCVR": waterRotationalVelocity = try reader.readFloat3()
        case "XCZR": try waterCurrentLinks.append(WaterCurrentLink(reference: reader.readFormID()))
        case "XCZC": try waterCurrentLinks.append(WaterCurrentLink(cell: reader.readFormID()))
        case "XCZA":
            if waterCurrentLinks.isEmpty {
                waterCurrentLinks.append(WaterCurrentLink())
            }
            waterCurrentLinks[waterCurrentLinks.count - 1].unknown = field.data
        case "XLTW": try litWater.append(reader.readFormID())
        case "XPWR":
            let reference = try reader.readFormID()
            let type = reader.bytesRemaining >= 4 ? try reader.readUInt32() : nil
            waterReflections.append(WaterReflection(reference: reference, type: type))
        default: return false
        }
        return true
    }

    private mutating func decodeScalar(
        _ field: ESMField,
        _ reader: inout BinaryReader
    ) throws -> Bool {
        switch field.type {
        case "EDID": editorID = try reader.readZString()
        case "XAPD": parentActivateOnly = try reader.readUInt8() != 0
        case "XLCM": levelModifier = try reader.readInt32()
        case "XTRI": collisionLayer = try reader.readUInt32()
        case "XCHG": charge = try reader.readFloat32()
        case "XACT": actionFlags = try reader.readUInt32()
        case "XHTW": headTrackingWeight = try reader.readFloat32()
        case "XFVC": favorCost = try reader.readFloat32()
        case "XHLP": health = try reader.readFloat32()
        case "ONAM": opensByDefault = true
        case "XIS2", "XIBS": isIgnoredBySandbox = true
        default: return try decodeActorField(field, &reader)
        }
        return true
    }

    /// Fields REFR reads itself, so only an ACHR reaches them here.
    private mutating func decodeActorField(
        _ field: ESMField,
        _ reader: inout BinaryReader
    ) throws -> Bool {
        switch field.type {
        case "XLKR": PlacedReference.appendLinkedReference(field.data, to: &linkedReferences)
        case "XRNK": ownerRank = try reader.readInt32()
        case "XCNT": count = try reader.readInt32()
        case "XRDS": radius = try reader.readFloat32()
        default: return false
        }
        return true
    }

    private mutating func decodeStructure(
        _ field: ESMField,
        _ reader: inout BinaryReader
    ) throws -> Bool {
        switch field.type {
        case "XMBO": boundHalfExtents = try reader.readFloat3()
        case "XOCP":
            occlusionPlane = try Plane(
                size: SIMD2(reader.readFloat32(), reader.readFloat32()),
                position: reader.readFloat3(),
                rotation: SIMD4(
                    reader.readFloat32(),
                    reader.readFloat32(),
                    reader.readFloat32(),
                    reader.readFloat32()
                )
            )
        case "XRGD":
            while reader.bytesRemaining >= 28 {
                let bone = try reader.readUInt8()
                reader.skip(3)
                try ragdollBones.append(RagdollBone(
                    boneID: bone, position: reader.readFloat3(), rotation: reader.readFloat3()
                ))
            }
        case "XRGB": ragdollBipedRotation = try reader.readFloat3()
        case "XLIG": lightData = try LightData(&reader)
        case "XALP": alpha = try SIMD2(reader.readUInt8(), reader.readUInt8())
        default: return try decodeLink(field, &reader)
        }
        return true
    }

    private mutating func decodeLink(
        _ field: ESMField,
        _ reader: inout BinaryReader
    ) throws -> Bool {
        switch field.type {
        case "XAPR":
            try activateParents.append(ActivateParent(
                reference: reader.readFormID(),
                delay: reader.readFloat32()
            ))
        case "XNDP": navmeshDoor = try NavmeshDoorLink(
                navmesh: reader.readFormID(),
                triangle: reader.readInt16()
            )
        case "XLRT":
            while reader.bytesRemaining >= 4 {
                try locationRefTypes.append(reader.readFormID())
            }
        case "XLOD": distantLOD = try reader.readFloat3()
        case "XCLP": linkColors = try SIMD8((0 ..< 8).map { _ in try reader.readUInt8() })
        default: return false
        }
        return true
    }
}

nonisolated extension PlacedReferenceDetails.LightData {
    init(_ reader: inout BinaryReader) throws {
        fieldOfViewOffset = try reader.readFloat32()
        fadeOffset = try reader.readFloat32()
        endDistanceCap = try reader.readFloat32()
        shadowDepthBias = try reader.readFloat32()
        unknown = reader.bytesRemaining >= 4 ? try reader.readUInt32() : nil
    }
}
