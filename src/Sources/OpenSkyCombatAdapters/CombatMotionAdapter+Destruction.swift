// The destructible objects a weapon can strike, and the hit damage they take through
// the script bridge. See docs/engine/papyrus-destruction.md#in-the-game.

import OpenSkyCells
public import OpenSkyFormatsESM
public import OpenSkyPhysics
import OpenSkySessionInterface
import OpenSkyWorldState
import simd

extension CombatMotionAdapter {
    /// The resident placed objects with `DEST` data inside the radius. Actors are left out.
    public func destructibleObjects(
        within radius: Float, of center: SIMD3<Float>
    ) -> [MeleeTarget] {
        guard radius > 0, let bridge = game.scripts.bridge else { return [] }
        return residentEntries().compactMap { entry in
            guard let placed = entry.placedReference else { return nil }
            let position = placed.placement.position
            guard
                simd_distance(position, center) <= radius,
                bridge.destructionHealthLeft(of: entry.key) != nil
            else { return nil }
            return MeleeTarget(key: entry.key, feet: position)
        }
    }

    /// A weapon hit is external damage, so Ignore External Damage holds it.
    public func damageDestructible(_ object: ReferenceKey, amount: Float) -> Bool {
        game.scripts.bridge?.damageDestructible(object, amount: amount, forced: false) ?? false
    }

    public func destructibleKey(reference: FormID) -> ReferenceKey? {
        residentEntries().first { $0.formID == reference && $0.placedReference != nil }?.key
    }

    private func residentEntries() -> [RuntimeReferenceEntry] {
        let streamer = game.streamer
        if let interior = streamer.interiorScene {
            return interior.references.sortedEntries()
        }
        return streamer.composition.cells.values.flatMap { $0.references.sortedEntries() }
    }
}
