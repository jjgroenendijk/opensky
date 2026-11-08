// Which linked actors walk through the vehicles' moving collision. See
// docs/engine/vehicles.md.

public import OpenSkyFormatsESM
import OpenSkyWorldInterface
import OpenSkyWorldState

nonisolated extension VehicleCore {
    /// Every rider, which moves with its seat, and every actor linked by any chain of
    /// links to a towed cart. An escort's horse is in neither, so a cart blocks it.
    public var cartGroups: Set<ReferenceKey> {
        var neighbours: [ReferenceKey: [ReferenceKey]] = [:]
        for (follower, link) in links {
            neighbours[follower, default: []].append(link.carrier)
            neighbours[link.carrier, default: []].append(follower)
        }
        var group = Set(links.keys)
        var pending = links.compactMap { follower, link -> ReferenceKey? in
            if case .towed = link.seat {
                return follower
            }
            return nil
        }
        var visited: Set<ReferenceKey> = []
        while let next = pending.popLast() {
            guard visited.insert(next).inserted else { continue }
            group.insert(next)
            pending += neighbours[next] ?? []
        }
        return group
    }
}
