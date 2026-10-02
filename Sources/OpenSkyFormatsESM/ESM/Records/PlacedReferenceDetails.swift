// REFR and ACHR fields that no runtime reads yet: rooms and portals, ragdoll
// pose, water currents, activate parents, patrol data, and editor links.
// Layout and sources: docs/formats/placed-references.md.

import Foundation

nonisolated public struct PlacedReferenceDetails: Equatable, Sendable {
    /// XOCP: a plane of the given size, placed and turned by a quaternion.
    public struct Plane: Equatable, Sendable {
        public let size: SIMD2<Float>
        public let position: SIMD3<Float>
        public let rotation: SIMD4<Float>
    }

    /// XPOD entry.
    public struct Portal: Equatable, Sendable {
        public let origin: FormID?
        public let destination: FormID?
    }

    /// XRMR header, then LNAM, INAM, and XLRM.
    public struct Room: Equatable, Sendable {
        public var linkedRoomCount: UInt8 = 0
        public var flags: UInt8 = 0
        public var lightingTemplate: FormID?
        public var imageSpace: FormID?
        public var linkedRooms: [FormID] = []
    }

    /// XRGD entry, 28 bytes.
    public struct RagdollBone: Equatable, Sendable {
        public let boneID: UInt8
        public let position: SIMD3<Float>
        public let rotation: SIMD3<Float>
    }

    /// XPWR. The type is absent on the 4-byte form.
    public struct WaterReflection: Equatable, Sendable {
        public let reference: FormID
        /// 0x01 reflection, 0x02 refraction.
        public let type: UInt32?
    }

    /// XLIG, 16 or 20 bytes.
    public struct LightData: Equatable, Sendable {
        public let fieldOfViewOffset: Float
        public let fadeOffset: Float
        public let endDistanceCap: Float
        public let shadowDepthBias: Float
        public let unknown: UInt32?
    }

    /// XAPR.
    public struct ActivateParent: Equatable, Sendable {
        public let reference: FormID
        public let delay: Float
    }

    /// XNDP.
    public struct NavmeshDoorLink: Equatable, Sendable {
        public let navmesh: FormID
        public let triangle: Int16
    }

    /// PDTO: a DIAL, or a 4-character topic subtype.
    public struct PatrolTopic: Equatable, Sendable {
        public let type: UInt32
        public let topic: FormID?
        public let subtype: String?
    }

    /// XPRD opens a patrol stop; XPPA, INAM, PDTO, and TNAM belong to it.
    public struct Patrol: Equatable, Sendable {
        public var idleTime: Float?
        public var hasScriptMarker = false
        public var idle: FormID?
        public var topics: [PatrolTopic] = []
        /// ACHR TNAM, a DIAL.
        public var topic: FormID?
    }

    /// XCZR or XCZC, then XCZA.
    public struct WaterCurrentLink: Equatable, Sendable {
        public var reference: FormID?
        public var cell: FormID?
        public var unknown: Data?
    }

    public var editorID: String?
    /// XMBO.
    public var boundHalfExtents: SIMD3<Float>?
    public var occlusionPlane: Plane?
    public var portals: [Portal] = []
    public var room: Room?
    /// XMBP.
    public var isMultiBoundPrimitive = false
    public var ragdollBones: [RagdollBone] = []
    /// XRGB.
    public var ragdollBipedRotation: SIMD3<Float>?
    public var waterReflections: [WaterReflection] = []
    /// XLTW, REFR waters this light lights.
    public var litWater: [FormID] = []
    public var lightData: LightData?
    /// XALP: cutoff and base alpha.
    public var alpha: SIMD2<UInt8>?
    /// XWCN or XWCS, the declared XWCU count.
    public var waterVelocityCount: UInt32?
    public var waterVelocities: [CellExtras.WaterVelocity] = []
    /// XCVL and XCVR.
    public var waterLinearVelocity: SIMD3<Float>?
    public var waterRotationalVelocity: SIMD3<Float>?
    public var waterCurrentLinks: [WaterCurrentLink] = []
    /// XAPD.
    public var parentActivateOnly: Bool?
    public var activateParents: [ActivateParent] = []
    /// XLCM: 0 easy, 1 medium, 2 hard, 3 very hard.
    public var levelModifier: Int32?
    /// XTRI, a COLL index.
    public var collisionLayer: UInt32?
    public var navmeshDoor: NavmeshDoorLink?
    /// XLRT, LCRT records.
    public var locationRefTypes: [FormID] = []
    /// XIS2 or XIBS.
    public var isIgnoredBySandbox = false
    /// XCHG.
    public var charge: Float?
    public var patrols: [Patrol] = []
    /// XACT: 0x01 use default, 0x02 activate, 0x04 open, 0x08 open by default.
    public var actionFlags: UInt32?
    /// XHTW.
    public var headTrackingWeight: Float?
    /// XFVC.
    public var favorCost: Float?
    /// ONAM.
    public var opensByDefault = false
    /// XLOD: three floats xEdit leaves unnamed.
    public var distantLOD: SIMD3<Float>?
    /// XHLP.
    public var health: Float?
    /// XCLP: link start and end colors.
    public var linkColors: SIMD8<UInt8>?
    /// FormID links, keyed by their signature: XTNM, XMBR, XSPC, XLIB, XLCN, XEZN, XLRL,
    /// XATR, XHOR, XMRC, and on ACHR XOWN and XEMI.
    public var links: [String: FormID] = [:]
    /// ACHR XLKR, XRNK, XCNT, and XRDS, which REFR reads itself.
    public var linkedReferences: [PlacedReference.LinkedReference] = []
    public var ownerRank: Int32?
    public var count: Int32?
    public var radius: Float?

    public init() {}
}
