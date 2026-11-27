// World item interaction: take a loose item, open a container, drop an item.
// No UI here. Each change is one `WorldStateStore` write: a take adds to the
// inventory and deletes the reference (or resets a spawned one); a drop writes a
// `ReferenceSpawnState`. Inventory arithmetic runs first, so a failure writes
// nothing. See docs/engine/interaction.md.

import Foundation
public import OpenSkyCrimeInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyWorldInterface
public import OpenSkyWorldState
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

/// Takes, drops and container sessions on top of `InventoryRuntime`.
@MainActor
public final class WorldItemRuntime {
    /// How far below the camera a dropped object is released, in game units: about
    /// eye-to-ground height. An object with a simulated Havok body falls from here
    /// as a dynamic body; one without comes to rest here.
    public static let dropHeight: Float = 100
    /// `fPlayerDropDistance`: how far in front of the dropper, at scale 1, an item lands.
    public var dropDistance: Float = 100
    /// The turn the player's next drop takes from the camera's direction, in radians.
    public private(set) var dropTurn: Float = 0

    public let inventory: InventoryRuntime

    /// The weight of one item of a base form, or nil when no item record has it.
    public func weight(of base: FormID) -> Float? {
        inventory.baselines.items.definition(base)?.weight
    }

    /// Resident reference index, for resolving an activated FormID to its key and
    /// cell. Weak, because the owner also owns the streamer. It reuses
    /// `PapyrusWorldReferenceSource`, which has the three lookups needed.
    public weak var references: (any PapyrusWorldReferenceSource)?

    /// The player's inventory holder, which is the destination of every take
    /// and the source of every drop.
    public let player = InventoryHolder.player

    /// Where a take asks whether it is theft. Nil without a crime runtime, where
    /// every take is honest.
    public let crime: (any CrimeReporting)?

    public var store: WorldStateStore {
        inventory.store
    }

    public init(
        inventory: InventoryRuntime,
        references: (any PapyrusWorldReferenceSource)? = nil,
        crime: (any CrimeReporting)? = nil
    ) {
        self.inventory = inventory
        self.references = references
        self.crime = crime
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

    /// True when taking the item behind `interaction` is theft.
    public func isTheft(_ interaction: PlacedInteraction) -> Bool {
        guard let entry = references?.referenceEntry(formID: interaction.reference) else {
            return false
        }
        return crime?.verdict(on: entry.key, item: interaction.base).isTheft ?? false
    }

    /// Whether the door or other openable behind `interaction` stands open now.
    public func isOpen(_ interaction: PlacedInteraction) -> Bool {
        guard let entry = references?.referenceEntry(formID: interaction.reference) else {
            return false
        }
        return store.component(ReferenceActivationState.self, for: entry.key)?.isOpen ?? false
    }

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
        let verdict = crime?.verdict(on: entry.key, item: interaction.base) ?? .unowned
        let copies = store.component(ItemCopyState.self, for: entry.key)?
            .copies(of: interaction.base, held: count) ?? []
        try inventory.add(
            interaction.base, count: count, to: player, stolen: verdict.isTheft, copies: copies
        )
        inventory.countPickUp(of: interaction.base, count: count, by: player)
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
    func removeFromWorld(_ key: ReferenceKey, cell: CellSceneLocation?) {
        if store.component(ReferenceSpawnState.self, for: key) != nil {
            store.reset(key)
            return
        }
        store.reset(ItemCopyState.componentKind, for: key)
        store.set(ReferenceDeletionState.deleted, for: key, in: cell)
    }

    // MARK: - Drop

    /// Removes `count` of `item` from the player and spawns it in the world at
    /// `placement`. The spawned stack keeps the item's distinct copies.
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
        try drop(item, count: count, from: player, at: placement)
    }

    /// `drop(_:count:at:)` from any holder, such as a dead actor's weapon falling.
    @discardableResult
    public func drop(
        _ item: FormID,
        count: Int32 = 1,
        from holder: InventoryHolder,
        at placement: DropPlacement
    ) throws -> ReferenceKey {
        let copies = inventory.leavingCopies(count, of: item, in: holder)
        try inventory.remove(item, count: count, from: holder)
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
        if holder == player {
            dropTurn = DropFan.advance(dropTurn, by: placement.fanStep)
        }
        // A dropped Legendary sword is still Legendary when picked up again.
        let distinct = ItemCopyState(copies: [item.rawValue: copies])
        if !distinct.isEmpty {
            store.set(distinct, for: key, in: placement.location)
        }
        return key
    }

    /// Where an item dropped from `eye` comes to rest: `reach` along `direction`, a
    /// standing height down. Nil `direction` drops it below the eye.
    public static func dropPlacement(
        in location: CellSceneLocation,
        eye: SIMD3<Float>,
        direction: SIMD3<Float>?,
        reach: DropReach
    ) -> DropPlacement {
        var placement = DropPlacement(
            location: location,
            position: eye + (direction ?? .zero) * reach.travel - SIMD3(0, 0, dropHeight)
        )
        placement.fanStep = DropFan.step(radius: reach.radius, distance: reach.distance)
        return placement
    }
}
