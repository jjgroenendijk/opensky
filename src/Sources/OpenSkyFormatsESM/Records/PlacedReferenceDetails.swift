// REFR and ACHR fields that no runtime reads yet: rooms and portals, ragdoll
// pose, water currents, activate parents, patrol data, and editor links.
// Layout and sources: docs/formats/placed-references.md.

public import Foundation

nonisolated public struct PlacedReferenceDetails: Equatable, Sendable {
    /// XOCP: a plane of the given size, placed and turned by a quaternion.
    struct Plane: Equatable, Sendable {
        let size: SIMD2<Float>
        let position: SIMD3<Float>
        let rotation: SIMD4<Float>
    }

    /// XPOD entry.
    public struct Portal: Equatable, Sendable {
        public let origin: FormID?
        public let destination: FormID?
    }

    /// XRMR header, then LNAM, INAM, and XLRM.
    public struct Room: Equatable, Sendable {
        var linkedRoomCount: UInt8 = 0
        var flags: UInt8 = 0
        var lightingTemplate: FormID?
        var imageSpace: FormID?
        public var linkedRooms: [FormID] = []
    }

    /// XRGD entry, 28 bytes.
    struct RagdollBone: Equatable, Sendable {
        let boneID: UInt8
        let position: SIMD3<Float>
        let rotation: SIMD3<Float>
    }

    /// XPWR. The type is absent on the 4-byte form.
    struct WaterReflection: Equatable, Sendable {
        let reference: FormID
        /// 0x01 reflection, 0x02 refraction.
        let type: UInt32?
    }

    /// XLIG, 16 or 20 bytes.
    struct LightData: Equatable, Sendable {
        let fieldOfViewOffset: Float
        let fadeOffset: Float
        let endDistanceCap: Float
        let shadowDepthBias: Float
        let unknown: UInt32?
    }

    /// XAPR.
    public struct ActivateParent: Equatable, Sendable {
        public let reference: FormID
        public let delay: Float
    }

    /// XNDP.
    struct NavmeshDoorLink: Equatable, Sendable {
        let navmesh: FormID
        let triangle: Int16
    }

    /// PDTO: a DIAL, or a 4-character topic subtype.
    struct PatrolTopic: Equatable, Sendable {
        let type: UInt32
        let topic: FormID?
        let subtype: String?
    }

    /// XPRD opens a patrol stop; XPPA, INAM, PDTO, and TNAM belong to it.
    struct Patrol: Equatable, Sendable {
        var idleTime: Float?
        var hasScriptMarker = false
        var idle: FormID?
        var topics: [PatrolTopic] = []
        /// ACHR TNAM, a DIAL.
        var topic: FormID?
    }

    /// XCZR or XCZC, then XCZA.
    struct WaterCurrentLink: Equatable, Sendable {
        var reference: FormID?
        var cell: FormID?
        var unknown: Data?
    }

    var editorID: String?
    /// XMBO.
    var boundHalfExtents: SIMD3<Float>?
    var occlusionPlane: Plane?
    public var portals: [Portal] = []
    public var room: Room?
    /// XMBP.
    var isMultiBoundPrimitive = false
    var ragdollBones: [RagdollBone] = []
    /// XRGB.
    var ragdollBipedRotation: SIMD3<Float>?
    var waterReflections: [WaterReflection] = []
    /// XLTW, REFR waters this light lights.
    var litWater: [FormID] = []
    var lightData: LightData?
    /// XALP: cutoff and base alpha.
    var alpha: SIMD2<UInt8>?
    /// XWCN or XWCS, the declared XWCU count.
    var waterVelocityCount: UInt32?
    public var waterVelocities: [CellExtras.WaterVelocity] = []
    /// XCVL and XCVR.
    public var waterLinearVelocity: SIMD3<Float>?
    public var waterRotationalVelocity: SIMD3<Float>?
    var waterCurrentLinks: [WaterCurrentLink] = []
    /// XAPD.
    public var parentActivateOnly: Bool?
    public var activateParents: [ActivateParent] = []
    /// XLCM: 0 easy, 1 medium, 2 hard, 3 very hard.
    public var levelModifier: Int32?
    /// XTRI, a COLL index.
    var collisionLayer: UInt32?
    var navmeshDoor: NavmeshDoorLink?
    /// XLRT, LCRT records.
    public var locationRefTypes: [FormID] = []
    /// XIS2 or XIBS.
    var isIgnoredBySandbox = false
    /// XCHG.
    var charge: Float?
    var patrols: [Patrol] = []
    /// XACT: 0x01 use default, 0x02 activate, 0x04 open, 0x08 open by default.
    var actionFlags: UInt32?
    /// XHTW.
    var headTrackingWeight: Float?
    /// XFVC.
    var favorCost: Float?
    /// ONAM.
    public var opensByDefault = false
    /// XLOD: three floats xEdit leaves unnamed.
    var distantLOD: SIMD3<Float>?
    /// XHLP.
    var health: Float?
    /// XCLP: link start and end colors.
    var linkColors: SIMD8<UInt8>?
    /// FormID links, keyed by their signature: XTNM, XMBR, XSPC, XLIB, XLCN, XEZN, XLRL,
    /// XATR, XHOR, XMRC, and on ACHR XOWN and XEMI.
    public var links: [String: FormID] = [:]
    /// ACHR XLKR, XRNK, XCNT, and XRDS, which REFR reads itself.
    public var linkedReferences: [PlacedReference.LinkedReference] = []
    var ownerRank: Int32?
    var count: Int32?
    var radius: Float?

    public init() {}
}
