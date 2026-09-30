// World item interaction: take a loose item, open a container, drop an item.
// No UI here. Each change is one `WorldStateStore` write: a take adds to the
// inventory and deletes the reference (or resets a spawned one); a drop writes a
// `ReferenceSpawnState`. Inventory arithmetic runs first, so a failure writes
// nothing. See docs/engine/interaction.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Failures the world-item layer reports. Inventory arithmetic failures are
/// `InventoryError` and pass straight through; these are the ones about the
/// world rather than about the items.
nonisolated public enum WorldItemError: Error, Equatable {
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
nonisolated public struct WorldTakeOutcome: Equatable, Sendable {
    /// The base item that entered the inventory.
    public let item: FormID
    /// How many, from the reference's XCNT or its spawned stack count.
    public let count: Int32
    /// Whether the take was theft, which marks the stack stolen. False for an unowned
    /// item and for one this actor may use.
    public let stolen: Bool
    /// Bounty the take accrued, which is zero when nobody saw it, when the
    /// place answers to no crime faction, and whenever the take was not theft.
    public let bounty: Int32

    public init(
        item: FormID,
        count: Int32,
        stolen: Bool = false,
        bounty: Int32 = 0
    ) {
        self.item = item
        self.count = count
        self.stolen = stolen
        self.bounty = bounty
    }
}

/// Where a dropped object lands.
nonisolated public struct DropPlacement: Equatable, Sendable {
    /// Cell the object comes to rest in. The caller supplies it because only
    /// the streamer knows which cell the player is standing in.
    public let location: CellSceneLocation
    public let position: SIMD3<Float>
    public let rotation: SIMD3<Float>

    public init(
        location: CellSceneLocation,
        position: SIMD3<Float>,
        rotation: SIMD3<Float> = .zero
    ) {
        self.location = location
        self.position = position
        self.rotation = rotation
    }
}

/// Takes, drops and container sessions on top of `InventoryRuntime`.
@MainActor
public final class WorldItemRuntime {
    /// How far below the camera a dropped object is released, in game units: about
    /// eye-to-ground height. An object with a simulated Havok body falls from here
    /// as a dynamic body; one without comes to rest here.
    public static let dropHeight: Float = 100
    /// How far in front of the camera a dropped object is placed, so it does
    /// not land inside the player capsule and immediately re-target itself.
    public static let dropForwardOffset: Float = 60

    public let inventory: InventoryRuntime
    /// Resident reference index, for resolving an activated FormID to its key and
    /// cell. Weak, because the owner also owns the streamer. It reuses
    /// `PapyrusWorldReferenceSource`, which has the three lookups needed.
    public weak var references: (any PapyrusWorldReferenceSource)?

    /// The player's inventory holder, which is the destination of every take
    /// and the source of every drop.
    public let player = InventoryHolder.player

    /// Where a take asks whether it is theft. Nil without a crime runtime, where
    /// every take is honest.
    public var crime: (any CrimeReporting)?

    public var store: WorldStateStore {
        inventory.store
    }

    public init(
        inventory: InventoryRuntime,
        references: (any PapyrusWorldReferenceSource)? = nil
    ) {
        self.inventory = inventory
        self.references = references
    }

    /// The same holder for an entry already in hand, so a caller that resolved
    /// one (the nearest-actor lookup) does not resolve it twice.
    public func actorHolder(entry: RuntimeReferenceEntry, base: FormID) -> InventoryHolder {
        InventoryHolder(
            key: entry.key,
            owner: .actor(base: base),
            cell: references?.cellLocation(of: entry.key)
        )
    }

    // MARK: - Take

    /// Moves the item behind `interaction` into the player's inventory and removes
    /// its reference from the world.
    /// - Throws: `WorldItemError.notTakeable`, `WorldItemError.unknownReference`, or
    ///   `InventoryError.countOverflow`. Nothing is written then.
    @discardableResult
    public func take(_ interaction: PlacedInteraction) throws -> WorldTakeOutcome {
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

    /// Takes an object out of the world. A plugin placement gets a
    /// `ReferenceDeletionState`; a spawned object has its whole delta reset, so it
    /// leaves nothing in the next save.
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
    public func drop(
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

    /// Where an object dropped from `eye` looking along `forward` comes to rest: a
    /// short step in front, a standing height down. `forward` is flattened first; a
    /// vertical look drops the object straight below the eye.
    public static func dropPlacement(
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

    /// Opens a transfer session on the container behind `interaction`, and records
    /// the opening in `ReferenceActivationState` so scripts can see it.
    /// - Throws: `WorldItemError.notAContainer`, `WorldItemError.unknownReference`.
    public func openContainer(_ interaction: PlacedInteraction) throws -> ContainerSession {
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
