// World item interaction (issue #177, roadmap item 12.1.3): taking a loose
// item out of the world, opening a container, and dropping something back.
//
// Headless and menu-free. Nothing here draws, and nothing here knows what a
// menu is: #289 and #179 put UI in front of these calls later, and until then
// the sidebar panel and the tests drive them directly. That is deliberate —
// picking an object up is a world operation, not a UI event, and the engine
// should be able to do it with no interface attached at all.
//
// Every world change is one `WorldStateStore` write, so the journal, the dirty
// counts, the per-cell rebuild and the save all see it without this file
// arranging any of them:
//
// * Take is `InventoryRuntime.add` followed by removing the reference —
//   `ReferenceDeletionState` for a plugin placement, a full `reset` for a
//   spawned one, because a spawned object that no longer exists should leave
//   nothing behind in the save rather than a tombstone that grows forever.
// * Drop is `InventoryRuntime.remove` followed by one `ReferenceSpawnState`
//   under a freshly allocated generated key.
// * A container session is `InventoryRuntime.transfer` in both directions.
//
// Ordering inside each operation is chosen so a failure writes nothing: the
// throwing inventory arithmetic runs first, and the world write happens only
// once it has succeeded. A take that would overflow the player's stack
// therefore leaves the item lying in the world rather than deleting it into
// nowhere.
//
// Documented in docs/engine/interaction.md.

import Foundation
import simd

/// Failures the world-item layer reports. Inventory arithmetic failures are
/// `InventoryError` and pass straight through; these are the ones about the
/// world rather than about the items.
nonisolated enum WorldItemError: Error, Equatable {
    /// The activated reference is not in any resident cell's runtime index, so
    /// there is nothing to identify, remove or attribute the change to.
    case unknownReference(FormID)
    /// The activated reference is not a loose item — its interaction action is
    /// something other than `.take`.
    case notTakeable(FormID)
    /// The activated reference is not a container.
    case notAContainer(FormID)
}

/// What one successful take moved.
nonisolated struct WorldTakeOutcome: Equatable, Sendable {
    /// The reference that left the world.
    let key: ReferenceKey
    /// The base item that entered the inventory.
    let item: FormID
    /// How many, from the reference's XCNT or its spawned stack count.
    let count: Int32
    /// Whether the take was theft, which is what marks the stack stolen
    /// (issue #504). False for an unowned item and for one this actor may use.
    let stolen: Bool
    /// Bounty the take accrued, which is zero when nobody saw it, when the
    /// place answers to no crime faction, and whenever the take was not theft.
    let bounty: Int32

    init(
        key: ReferenceKey,
        item: FormID,
        count: Int32,
        stolen: Bool = false,
        bounty: Int32 = 0
    ) {
        self.key = key
        self.item = item
        self.count = count
        self.stolen = stolen
        self.bounty = bounty
    }
}

/// Where a dropped object lands.
nonisolated struct DropPlacement: Equatable, Sendable {
    /// Cell the object comes to rest in. The caller supplies it because only
    /// the streamer knows which cell the player is standing in.
    let location: CellSceneLocation
    let position: SIMD3<Float>
    let rotation: SIMD3<Float>

    init(location: CellSceneLocation, position: SIMD3<Float>, rotation: SIMD3<Float> = .zero) {
        self.location = location
        self.position = position
        self.rotation = rotation
    }
}

/// Takes, drops and container sessions on top of `InventoryRuntime`.
@MainActor
final class WorldItemRuntime {
    /// How far below the camera a dropped object is released, in game units.
    ///
    /// Roughly the distance from a standing actor's eye to the ground, so an
    /// item dropped on flat ground starts at the player's feet rather than at
    /// eye level or inside the terrain.
    ///
    /// This is the *release* pose, not necessarily the resting one. Since issue
    /// #193 a dropped object whose mesh carries a simulated Havok body becomes a
    /// dynamic rigid body on the next build of its cell and settles from here
    /// under gravity — the drop writes a `ReferenceSpawnState` and the ordinary
    /// collision build does the rest, so nothing in this file knows about
    /// physics. An object whose mesh carries no dynamic body still comes to rest
    /// exactly here, which is why the offset is a plausible resting height
    /// rather than an arm's length.
    static let dropHeight: Float = 100
    /// How far in front of the camera a dropped object is placed, so it does
    /// not land inside the player capsule and immediately re-target itself.
    static let dropForwardOffset: Float = 60

    let inventory: InventoryRuntime
    /// Resident reference index, for resolving an activated FormID to its
    /// runtime key and cell. Weak because the controller that owns this also
    /// owns the streamer behind it.
    ///
    /// `PapyrusWorldReferenceSource` is reused rather than duplicated: it
    /// already declares exactly the three lookups this needs, and `CellStreamer`
    /// already conforms. The name says Papyrus because that milestone
    /// introduced it, not because the seam is Papyrus-specific.
    weak var references: (any PapyrusWorldReferenceSource)?

    /// The player's inventory holder, which is the destination of every take
    /// and the source of every drop.
    let player = InventoryHolder.player

    /// Where a take asks whether it is theft, and says so when it is (issue
    /// #504). Nil in a session with no crime runtime — a synthetic scene, or a
    /// load order with no FACT data — where every take is an honest one, which
    /// is the behaviour this file had before crime existed.
    var crime: CrimeReporter?

    var store: WorldStateStore {
        inventory.store
    }

    init(
        inventory: InventoryRuntime,
        references: (any PapyrusWorldReferenceSource)? = nil
    ) {
        self.inventory = inventory
        self.references = references
    }

    /// The inventory holder for one resident ACHR, or nil when nothing
    /// resident is that reference or it is not an actor (issue #178).
    ///
    /// An actor's holder needs all three of its key, its NPC_ base — which is
    /// where `InventoryBaselineResolver` reads the default outfit from — and
    /// its cell, so that an equip is attributed to the cell whose rebuild makes
    /// it visible. Only the entry knows all three, which is why this lives
    /// beside the other holder-building call sites rather than at the UI.
    func actorHolder(formID: FormID) -> InventoryHolder? {
        guard
            let entry = references?.referenceEntry(formID: formID),
            let actor = entry.placedActor
        else { return nil }
        return actorHolder(entry: entry, base: actor.base)
    }

    /// The same holder for an entry already in hand, so a caller that resolved
    /// one (the nearest-actor lookup) does not resolve it twice.
    func actorHolder(entry: RuntimeReferenceEntry, base: FormID) -> InventoryHolder {
        InventoryHolder(
            key: entry.key,
            owner: .actor(base: base),
            cell: references?.cellLocation(of: entry.key)
        )
    }

    // MARK: - Take

    /// Moves the item behind `interaction` into the player's inventory and
    /// removes its reference from the world.
    ///
    /// - Throws: `WorldItemError.notTakeable` when the interaction is not a
    ///   `.take`, `WorldItemError.unknownReference` when nothing resident holds
    ///   it, and `InventoryError.countOverflow` when the player's stack cannot
    ///   grow. Nothing is written in any of those cases.
    @discardableResult
    func take(_ interaction: PlacedInteraction) throws -> WorldTakeOutcome {
        guard interaction.action == .take else {
            throw WorldItemError.notTakeable(interaction.reference)
        }
        guard let entry = references?.referenceEntry(formID: interaction.reference) else {
            throw WorldItemError.unknownReference(interaction.reference)
        }
        let count = Self.stackCount(of: entry)
        // Asked before the item moves, because once it is in the inventory the
        // reference is gone and there is nothing left to ask about.
        let verdict = crime?.verdict(on: entry.key) ?? .unowned
        try inventory.add(
            interaction.base, count: count, to: player, stolen: verdict.isTheft
        )
        // Reported before the reference leaves the world, for the reason the
        // verdict is read before the item moves: the crime is located by where
        // the stolen thing stood, and only a resident reference can say where
        // that was.
        let bounty = verdict.isTheft
            ? crime?.reportTheft(
                of: interaction.base,
                count: count,
                from: entry.key,
                owner: verdict.owner
            ).gold ?? 0
            : 0
        removeFromWorld(entry.key, cell: references?.cellLocation(of: entry.key))
        return WorldTakeOutcome(
            key: entry.key,
            item: interaction.base,
            count: count,
            stolen: verdict.isTheft,
            bounty: bounty
        )
    }

    /// How many individual items one placed reference stands for: its XCNT, or
    /// its spawned stack count, or one. A non-positive XCNT — which the format
    /// allows and mods do write — reads as one, because a reference that is
    /// placed in the world is at least one item.
    private static func stackCount(of entry: RuntimeReferenceEntry) -> Int32 {
        guard let reference = entry.placedReference, let count = reference.itemCount else {
            return 1
        }
        return max(1, count)
    }

    /// Takes an object out of the world.
    ///
    /// A plugin placement gets a `ReferenceDeletionState`, which the cell build
    /// honours exactly as it honours a script's `Delete()`. A spawned object
    /// instead has its whole delta reset: it exists only because the store says
    /// so, so dropping the state is what makes it gone, and it leaves nothing
    /// behind in the next save.
    private func removeFromWorld(_ key: ReferenceKey, cell: CellSceneLocation?) {
        if store.component(ReferenceSpawnState.self, for: key) != nil {
            store.reset(key)
            return
        }
        store.set(ReferenceDeletionState.deleted, for: key, in: cell)
    }

    // MARK: - Drop

    /// Removes `count` of `item` from the player and spawns it in the world at
    /// `placement`.
    ///
    /// - Returns: the generated key the new reference is addressed by.
    /// - Throws: `InventoryError.insufficientCount` when the player holds
    ///   fewer, in which case nothing is written and no key is allocated.
    @discardableResult
    func drop(
        _ item: FormID,
        count: Int32 = 1,
        at placement: DropPlacement
    ) throws -> ReferenceKey {
        try inventory.remove(item, count: count, from: player)
        let key = store.allocateGeneratedKey()
        store.set(
            ReferenceSpawnState(
                base: item,
                location: placement.location,
                placement: PlacedReference.Placement(
                    position: placement.position, rotation: placement.rotation
                ),
                count: count
            ),
            for: key,
            in: placement.location
        )
        return key
    }

    /// Where an object dropped by a player looking along `forward` from `eye`
    /// comes to rest: a short step in front, a standing height down.
    ///
    /// The forward vector is flattened onto the ground plane first, so looking
    /// at the sky does not throw the item over the player's head. A camera
    /// pointing straight up or straight down leaves nothing to flatten, and the
    /// object lands directly below the eye.
    static func dropPlacement(
        in location: CellSceneLocation,
        eye: SIMD3<Float>,
        forward: SIMD3<Float>
    ) -> DropPlacement {
        let flat = SIMD2(forward.x, forward.y)
        let length = simd_length(flat)
        let offset = length > 1e-4
            ? SIMD3(flat.x / length, flat.y / length, 0) * dropForwardOffset
            : SIMD3<Float>.zero
        return DropPlacement(
            location: location,
            position: eye + offset - SIMD3(0, 0, dropHeight)
        )
    }

    // MARK: - Containers

    /// Opens a transfer session on the container behind `interaction`.
    ///
    /// Opening is a world change in its own right — `ReferenceActivationState`
    /// records it, so a script asking whether the chest has been opened gets a
    /// true answer — and it is written here rather than in the Papyrus
    /// activation bridge, because only the session knows whether one is live.
    ///
    /// - Throws: `WorldItemError.notAContainer` for a non-`.search`
    ///   interaction, `WorldItemError.unknownReference` when nothing resident
    ///   holds it.
    func openContainer(_ interaction: PlacedInteraction) throws -> ContainerSession {
        guard interaction.action == .search else {
            throw WorldItemError.notAContainer(interaction.reference)
        }
        guard let entry = references?.referenceEntry(formID: interaction.reference) else {
            throw WorldItemError.unknownReference(interaction.reference)
        }
        let session = ContainerSession(
            runtime: self,
            container: InventoryHolder(
                key: entry.key,
                owner: .container(base: interaction.base),
                cell: references?.cellLocation(of: entry.key)
            )
        )
        session.setOpen(true)
        return session
    }
}
