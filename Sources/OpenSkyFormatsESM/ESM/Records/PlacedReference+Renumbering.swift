// REFR and ACHR FormIDs moved into another FormID space, so a reference from a
// later plugin can join a cell of the load order (docs/formats/formid.md).

import Foundation

nonisolated extension PlacedReference: FormIDRenumbering {
    public func renumbered(_ translate: (FormID) -> FormID) -> PlacedReference {
        var copy = self
        copy.formID = translate(formID)
        copy.base = translate(base)
        copy.teleportDestination = teleportDestination.map {
            TeleportDestination(door: translate($0.door), placement: $0.placement, flags: $0.flags)
        }
        copy.emittance = emittance.renumbered(translate)
        copy.linkedReferences = linkedReferences.map { $0.renumbered(translate) }
        copy.owner = owner.renumbered(translate)
        copy.scriptData = scriptData.renumbered(translate)
        copy.lock = lock.map {
            LockData(
                level: $0.level,
                key: $0.key.renumbered(translate),
                flags: $0.flags,
                size: $0.size
            )
        }
        copy.enableParent = enableParent?.renumbered(translate)
        copy.details = details.renumbered(translate)
        return copy
    }
}

nonisolated extension PlacedActor: FormIDRenumbering {
    public func renumbered(_ translate: (FormID) -> FormID) -> PlacedActor {
        var copy = self
        copy.formID = translate(formID)
        copy.base = translate(base)
        copy.scriptData = scriptData.renumbered(translate)
        copy.enableParent = enableParent?.renumbered(translate)
        copy.details = details.renumbered(translate)
        return copy
    }
}

nonisolated extension PlacedReference.LinkedReference {
    func renumbered(_ translate: (FormID) -> FormID) -> Self {
        Self(keyword: keyword.renumbered(translate), ref: translate(ref))
    }
}

nonisolated extension EnableParent {
    func renumbered(_ translate: (FormID) -> FormID) -> EnableParent {
        var copy = self
        copy.parent = translate(parent)
        return copy
    }
}

nonisolated extension PlacedReferenceDetails {
    func renumbered(_ translate: (FormID) -> FormID) -> PlacedReferenceDetails {
        var copy = self
        copy.portals = portals.map {
            Portal(
                origin: $0.origin.renumbered(translate),
                destination: $0.destination.renumbered(translate)
            )
        }
        copy.room = room?.renumbered(translate)
        copy.waterReflections = waterReflections.map {
            WaterReflection(reference: translate($0.reference), type: $0.type)
        }
        copy.litWater = litWater.map(translate)
        copy.activateParents = activateParents.map {
            ActivateParent(reference: translate($0.reference), delay: $0.delay)
        }
        copy.navmeshDoor = navmeshDoor.map {
            NavmeshDoorLink(navmesh: translate($0.navmesh), triangle: $0.triangle)
        }
        copy.locationRefTypes = locationRefTypes.map(translate)
        copy.patrols = patrols.map { $0.renumbered(translate) }
        copy.waterCurrentLinks = waterCurrentLinks.map {
            var link = $0
            link.reference = $0.reference.renumbered(translate)
            link.cell = $0.cell.renumbered(translate)
            return link
        }
        copy.links = links.mapValues(translate)
        copy.linkedReferences = linkedReferences.map { $0.renumbered(translate) }
        return copy
    }
}

nonisolated extension PlacedReferenceDetails.Room {
    func renumbered(_ translate: (FormID) -> FormID) -> Self {
        var copy = self
        copy.lightingTemplate = lightingTemplate.renumbered(translate)
        copy.imageSpace = imageSpace.renumbered(translate)
        copy.linkedRooms = linkedRooms.map(translate)
        return copy
    }
}

nonisolated extension PlacedReferenceDetails.Patrol {
    func renumbered(_ translate: (FormID) -> FormID) -> Self {
        var copy = self
        copy.idle = idle.renumbered(translate)
        copy.topic = topic.renumbered(translate)
        copy.topics = topics.map {
            PlacedReferenceDetails.PatrolTopic(
                type: $0.type, topic: $0.topic.renumbered(translate), subtype: $0.subtype
            )
        }
        return copy
    }
}
