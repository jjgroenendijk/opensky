// Census probes for REFR and ACHR details.

import Foundation
@testable import OpenSkyFormatsESM

extension FieldCensus {
    mutating func countReference(_ reference: PlacedReference) {
        countDetails("REFR", reference.details)
        count("REFR map marker", reference.mapMarker, [
            ("isHiddenFromShowAll", { $0.isHiddenFromShowAll })
        ])
        tally("REFR", reference.skipped)
    }

    mutating func countActorReference(_ actor: PlacedActor) {
        countDetails("ACHR", actor.details)
        count("ACHR actor", actor.details, [
            ("ownerRank", { $0.ownerRank }), ("count", { $0.count }), ("radius", { $0.radius })
        ])
        tally("ACHR", actor.skipped)
    }

    private mutating func countDetails(_ owner: String, _ details: PlacedReferenceDetails) {
        count(owner, details, Self.referenceDetails)
        count("\(owner) activate parent", details.activateParents, [
            ("reference", { $0.reference })
        ])
        count("\(owner) light", details.lightData, [
            ("fieldOfViewOffset", { $0.fieldOfViewOffset }), ("fadeOffset", { $0.fadeOffset }),
            ("endDistanceCap", { $0.endDistanceCap }), ("shadowDepthBias", { $0.shadowDepthBias })
        ])
        count("\(owner) navmesh door", details.navmeshDoor, [
            ("navmesh", { $0.navmesh }), ("triangle", { $0.triangle })
        ])
        count("\(owner) patrol", details.patrols, [
            ("idleTime", { $0.idleTime }), ("topic", { $0.topic })
        ])
        count("\(owner) patrol topic", details.patrols.flatMap(\.topics), [
            ("type", { $0.type }), ("topic", { $0.topic })
        ])
        count("\(owner) occlusion plane", details.occlusionPlane, [
            ("size", { $0.size }), ("position", { $0.position }), ("rotation", { $0.rotation })
        ])
        count("\(owner) portal", details.portals, [
            ("origin", { $0.origin }), ("destination", { $0.destination })
        ])
        countRoomsAndWater(owner, details)
    }

    private mutating func countRoomsAndWater(_ owner: String, _ details: PlacedReferenceDetails) {
        count("\(owner) ragdoll bone", details.ragdollBones, [
            ("boneID", { $0.boneID }), ("rotation", { $0.rotation })
        ])
        count("\(owner) room", details.room, [
            ("linkedRoomCount", { $0.linkedRoomCount }), ("flags", { $0.flags }),
            ("lightingTemplate", { $0.lightingTemplate })
        ])
        count("\(owner) water current", details.waterCurrentLinks, [
            ("reference", { $0.reference }), ("cell", { $0.cell }), ("unknown", { $0.unknown })
        ])
        count("\(owner) water reflection", details.waterReflections, [
            ("reference", { $0.reference }), ("type", { $0.type })
        ])
    }

    static var referenceDetails: [Probe<PlacedReferenceDetails>] {
        [
            ("editorID", { $0.editorID }), ("boundHalfExtents", { $0.boundHalfExtents }),
            ("occlusionPlane", { $0.occlusionPlane }),
            ("ragdollBipedRotation", { $0.ragdollBipedRotation }), ("alpha", { $0.alpha }),
            ("waterVelocityCount", { $0.waterVelocityCount }),
            ("waterLinearVelocity", { $0.waterLinearVelocity }),
            ("waterRotationalVelocity", { $0.waterRotationalVelocity }),
            ("parentActivateOnly", { $0.parentActivateOnly }),
            ("collisionLayer", { $0.collisionLayer }), ("navmeshDoor", { $0.navmeshDoor }),
            ("charge", { $0.charge }), ("actionFlags", { $0.actionFlags }),
            ("headTrackingWeight", { $0.headTrackingWeight }), ("favorCost", { $0.favorCost }),
            ("distantLOD", { $0.distantLOD }), ("health", { $0.health }),
            ("linkColors", { $0.linkColors })
        ]
    }
}
