// A live handle on one container reference. `contents` is read through
// `InventoryRuntime` on every call, so a script that empties the chest shows at
// once. Every move goes through `InventoryRuntime.transfer`, which writes nothing
// when it fails, so item totals are conserved. See docs/engine/interaction.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyWorldState

/// A live transfer session between one container and the player.
@MainActor
public final class ContainerSession {
    /// The container being searched.
    public let container: InventoryHolder
    /// Whoever is doing the searching, which is the player today.
    public let player: InventoryHolder

    private let runtime: WorldItemRuntime

    private var inventory: InventoryRuntime {
        runtime.inventory
    }

    public init(runtime: WorldItemRuntime, container: InventoryHolder) {
        self.runtime = runtime
        self.container = container
        player = runtime.player
    }

    // MARK: - Reading

    /// What the container holds right now: its runtime inventory when anything
    /// has touched it, its re-derived CNTO baseline when nothing has.
    public var contents: [InventoryStack] {
        inventory.inventory(of: container).stacks
    }

    /// Total number of individual items in the container.
    public var totalCount: Int {
        inventory.inventory(of: container).totalCount
    }

    public var isEmpty: Bool {
        contents.isEmpty
    }

    /// Whether the store currently reads this container as open.
    public var isOpen: Bool {
        runtime.store.component(ReferenceActivationState.self, for: container.key)?.isOpen ?? false
    }

    // MARK: - Transfers

    /// Whether taking from this container is theft, and from whom. Not cached, so
    /// a key handed over while the chest is open changes the answer.
    public var ownership: OwnershipVerdict {
        runtime.crime?.verdict(on: container.key) ?? .unowned
    }

    /// Moves `count` of `item` to the player. Taking from an owned container marks
    /// the goods stolen and reports the crime (<https://en.uesp.net/wiki/Skyrim:Crime>).
    /// Returns the bounty; throws `InventoryError.insufficientCount`, writing nothing.
    @discardableResult
    public func take(_ item: FormID, count: Int32 = 1) throws -> Int32 {
        let verdict = ownership
        try inventory.transfer(
            item, count: count, from: container, to: player, markingStolen: verdict.isTheft
        )
        guard verdict.isTheft else { return 0 }
        return runtime.crime?.reportTheft(
            of: item, count: count, from: container.key, owner: verdict.owner
        ).gold ?? 0
    }

    /// Moves every stack to the player. Not atomic across stacks: only a count
    /// overflow can stop it, and a half-emptied chest beats a refusal.
    /// - Returns: the stacks that moved, in order.
    @discardableResult
    public func takeAll() throws -> [InventoryStack] {
        let moving = contents
        for stack in moving {
            try take(stack.item, count: stack.count)
        }
        return moving
    }

    /// Moves `count` of `item` from the player into the container.
    ///
    /// - Throws: `InventoryError.insufficientCount` when the player holds
    ///   fewer, which writes nothing.
    public func deposit(_ item: FormID, count: Int32 = 1) throws {
        try inventory.transfer(item, count: count, from: player, to: container)
    }

    // MARK: - Open state

    /// Records the container's open state. Set, not toggled: a door toggles once per
    /// swing, but a container stays open for the life of the session.
    public func setOpen(_ open: Bool) {
        let current = runtime.store
            .component(ReferenceActivationState.self, for: container.key)
            ?? .untouched
        guard current.isOpen != open else { return }
        runtime.store.set(
            ReferenceActivationState(
                activationCount: open ? current.activationCount &+ 1 : current.activationCount,
                isOpen: open,
                lastActivator: open ? .player : current.lastActivator
            ),
            for: container.key,
            in: container.cell
        )
    }

    /// Ends the session. Idempotent, so a caller that closes twice — a menu
    /// dismissed and then torn down — writes once.
    public func close() {
        setOpen(false)
    }
}
