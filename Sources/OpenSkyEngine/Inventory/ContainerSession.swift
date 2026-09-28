// Container transfer sessions (issue #177, roadmap item 12.1.3): the
// engine-level object a menu will eventually sit on top of.
//
// A session is a live handle on one container reference, not a snapshot of it.
// `contents` is read through `InventoryRuntime` every time it is asked for, so
// a script that empties the chest while the session is open is visible to the
// next read rather than being papered over by a stale copy. That is the same
// never-cache-a-baseline rule the rest of the runtime-state layer follows.
//
// Everything the session moves goes through `InventoryRuntime.transfer`, which
// computes both resulting inventories before writing either. A transfer that
// cannot complete therefore writes nothing at all and the total item count
// across the container and the player is unchanged — which is what makes
// `takeAll()` safe to describe as "conserving", one stack at a time.
//
// Documented in docs/engine/interaction.md.

import Foundation

/// A live transfer session between one container and the player.
@MainActor
final class ContainerSession {
    /// The container being searched.
    let container: InventoryHolder
    /// Whoever is doing the searching, which is the player today.
    let player: InventoryHolder

    private let runtime: WorldItemRuntime

    private var inventory: InventoryRuntime {
        runtime.inventory
    }

    init(runtime: WorldItemRuntime, container: InventoryHolder) {
        self.runtime = runtime
        self.container = container
        player = runtime.player
    }

    // MARK: - Reading

    /// What the container holds right now: its runtime inventory when anything
    /// has touched it, its re-derived CNTO baseline when nothing has.
    var contents: [InventoryStack] {
        inventory.inventory(of: container).stacks
    }

    /// Total number of individual items in the container.
    var totalCount: Int {
        inventory.inventory(of: container).totalCount
    }

    var isEmpty: Bool {
        contents.isEmpty
    }

    /// Whether the store currently reads this container as open.
    var isOpen: Bool {
        runtime.store.component(ReferenceActivationState.self, for: container.key)?.isOpen ?? false
    }

    // MARK: - Transfers

    /// Whether taking from this container would be theft, and who it would be
    /// theft from (issue #504).
    ///
    /// Read once per call rather than cached for the session's lifetime, for
    /// the reason `contents` is not cached: a quest that hands the player the
    /// key to a house while the chest is open must change the answer.
    var ownership: OwnershipVerdict {
        runtime.crime?.verdict(on: container.key) ?? .unowned
    }

    /// Moves `count` of `item` from the container to the player.
    ///
    /// Taking out of a container somebody else owns is theft: the goods arrive
    /// marked stolen and the bounty is reported. "Viewing items in an owned
    /// container, taking your own items out of an owned container, and taking
    /// items from a dead NPC are not considered stealing"
    /// (<https://en.uesp.net/wiki/Skyrim:Crime>) — the first and second of
    /// those are what `ownership` answers, and the third is why a corpse's
    /// container is left unowned by the session that builds it.
    ///
    /// - Returns: the bounty the take accrued, zero when it was no crime or
    ///   nobody saw.
    /// - Throws: `InventoryError.insufficientCount` when the container holds
    ///   fewer, which writes nothing.
    @discardableResult
    func take(_ item: FormID, count: Int32 = 1) throws -> Int32 {
        let verdict = ownership
        try inventory.transfer(
            item, count: count, from: container, to: player, markingStolen: verdict.isTheft
        )
        guard verdict.isTheft else { return 0 }
        return runtime.crime?.reportTheft(
            of: item, count: count, from: container.key, owner: verdict.owner
        ).gold ?? 0
    }

    /// Moves everything the container holds to the player, stack by stack.
    ///
    /// Not atomic across stacks, and deliberately so: the only way a later
    /// stack can fail is `countOverflow` on a player stack of over two billion,
    /// and stopping there having moved the earlier stacks is a better outcome
    /// than refusing to empty a chest. Each individual stack is still
    /// all-or-nothing, so no count is ever lost.
    ///
    /// - Returns: the stacks that moved, in the order they moved.
    @discardableResult
    func takeAll() throws -> [InventoryStack] {
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
    func deposit(_ item: FormID, count: Int32 = 1) throws {
        try inventory.transfer(item, count: count, from: player, to: container)
    }

    // MARK: - Open state

    /// Records the container's open state on `ReferenceActivationState`.
    ///
    /// Set explicitly rather than toggled. The Papyrus activation bridge
    /// toggles `isOpen` for doors, where one activation is one swing; a
    /// container's open state is the lifetime of a session, and only the
    /// session knows when that starts and ends. An activation that opens a
    /// session therefore records the state here and not there.
    func setOpen(_ open: Bool) {
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
    func close() {
        setOpen(false)
    }
}
