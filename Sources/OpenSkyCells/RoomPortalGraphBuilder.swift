// The room/portal graph of one interior, from its room markers (XRMR, XLRM)
// and portals (XPOD), each a box primitive (XPRM). Pure: references in, graph out.
// Roles and sources: docs/formats/placed-references.md#rooms-and-portals.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRendering
import simd

nonisolated public enum RoomPortalGraphBuilder: Sendable {
    /// Nil when the cell has no room with a usable box.
    public static func graph(references: [PlacedReference]) -> RoomPortalGraph? {
        var rooms: [OrientedBox] = []
        var roomIndex: [UInt32: Int32] = [:]
        var linkedRooms: [(Int32, [FormID])] = []
        for ref in references {
            guard
                let room = ref.details.room,
                let primitive = ref.primitive, primitive.type == .box,
                let box = box(of: ref, primitive)
            else { continue }
            let index = Int32(rooms.count)
            roomIndex[ref.formID.rawValue] = index
            rooms.append(box)
            linkedRooms.append((index, room.linkedRooms))
        }
        guard !rooms.isEmpty else { return nil }
        var portals: [RoomPortalGraph.Portal] = []
        for ref in references {
            guard
                let primitive = ref.primitive, primitive.type == .portalBox,
                let box = box(of: ref, primitive)
            else { continue }
            for entry in ref.details.portals {
                guard
                    let origin = entry.origin.flatMap({ roomIndex[$0.rawValue] }),
                    let destination = entry.destination.flatMap({ roomIndex[$0.rawValue] })
                else { continue }
                portals.append(RoomPortalGraph.Portal(box: box, rooms: SIMD2(origin, destination)))
            }
        }
        let links = linkedRooms.flatMap { index, linked in
            linked.compactMap { roomIndex[$0.rawValue].map { SIMD2(index, $0) } }
        }
        return RoomPortalGraph(rooms: rooms, portals: portals, links: links)
    }

    private static func box(
        of ref: PlacedReference,
        _ primitive: PlacedReference.Primitive
    ) -> OrientedBox? {
        OrientedBox(
            transform: MatrixMath.placement(
                position: ref.placement.position,
                rotation: ref.placement.rotation,
                scale: ref.scale
            ),
            halfExtents: primitive.halfExtents
        )
    }
}
