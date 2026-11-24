// Which linked actors walk through the vehicles' moving collision. See
// docs/engine/vehicles.md.

public import OpenSkyFormatsESM
import OpenSkyWorldInterface
import OpenSkyWorldState

nonisolated extension VehicleCore {
    /// Every rider, which moves with its seat, and every actor linked by any chain of
    /// links to a towed cart, with the towed carts of its own group. Such an actor walks
    /// through its own carts only: a second cart's horse is stopped by the first cart.
    /// An escort's horse is in no group, so every cart blocks it.
    public var ownCarts: [ReferenceKey: Set<ReferenceKey>] {
        var neighbours: [ReferenceKey: [ReferenceKey]] = [:]
        for (follower, link) in links {
            neighbours[follower, default: []].append(link.carrier)
            neighbours[link.carrier, default: []].append(follower)
        }
        var result = Dictionary(uniqueKeysWithValues: links.keys.map { ($0, Set<ReferenceKey>()) })
        for (cart, link) in links {
            guard case .towed = link.seat else { continue }
            var pending = [cart]
            var visited: Set<ReferenceKey> = []
            while let next = pending.popLast() {
                guard visited.insert(next).inserted else { continue }
                result[next, default: []].insert(cart)
                pending += neighbours[next] ?? []
            }
        }
        return result
    }

    public var cartGroups: Set<ReferenceKey> {
        Set(ownCarts.keys)
    }
}
