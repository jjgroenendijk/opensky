// Main-app world-item inspection seam (issue #177, roadmap item 12.1.3). The
// provider keeps the panel independent of `GameViewController` while exposing
// the engine-owned take, drop and container-session operations.
//
// One snapshot value rather than a bag of protocol properties, for the same
// reason `RuntimeStateSnapshot` is one: the readout has to be a pure function
// of a single engine observation, not of several taken microseconds apart while
// the streamer is mutating between them.
//
// AppKit-free, so it compiles into `openskycli` alongside the app.

import Foundation

/// One stack as the panel spells it: what it is, how many, and what to call it.
nonisolated struct ItemStackReadout: Equatable, Sendable {
    let item: FormID
    let count: Int32
    /// FULL name when the item index resolves one, else the editor ID, else the
    /// FormID. Never empty, so a readout line always names something.
    let name: String
}

/// One observation of the world-item runtime.
nonisolated struct ItemControlSnapshot: Equatable, Sendable {
    /// False when no inventory runtime is attached — no game data, or a demo
    /// scene. Every other field is then empty and the panel says so rather than
    /// showing a convincing zero.
    let isAvailable: Bool
    /// The crosshair target's name, when it has one.
    let targetName: String?
    /// Whether activating the current target would take it.
    let targetIsTakeable: Bool
    /// Whether activating the current target would open a container.
    let targetIsContainer: Bool
    /// The player's stacks, in the component's FormID order.
    let playerStacks: [ItemStackReadout]
    /// Total carried weight from #175's per-item weights.
    let playerWeight: Float
    /// Gold, which is an ordinary stack of the vanilla gold form.
    let playerGold: Int32
    /// The open container's name, or nil when no session is live.
    let containerName: String?
    /// The open container's contents, re-read every observation.
    let containerStacks: [ItemStackReadout]
    /// Objects the running game has spawned and not yet taken back — dropped
    /// items, across every cell whether resident or not.
    let spawnedObjectCount: Int
    /// Human-readable result of the last panel action.
    let lastActionText: String

    /// The reading with no runtime attached.
    static let unavailable = ItemControlSnapshot(
        isAvailable: false,
        targetName: nil,
        targetIsTakeable: false,
        targetIsContainer: false,
        playerStacks: [],
        playerWeight: 0,
        playerGold: 0,
        containerName: nil,
        containerStacks: [],
        spawnedObjectCount: 0,
        lastActionText: "World items unavailable: no game data loaded."
    )
}

@MainActor
protocol ItemControlProviding: AnyObject {
    var itemControlSnapshot: ItemControlSnapshot { get }

    /// Takes the crosshair target into the player's inventory.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func takeInteractionTarget() -> String

    /// Opens a container session on the crosshair target, replacing any
    /// session already open.
    @discardableResult
    func openInteractionTargetContainer() -> String

    /// Moves everything in the open container to the player.
    @discardableResult
    func takeAllFromOpenContainer() -> String

    /// Ends the open container session.
    @discardableResult
    func closeOpenContainer() -> String

    /// Drops `count` of `item` in front of the player. A nil `item` drops from
    /// the player's first stack, which is what makes the control usable without
    /// knowing a FormID.
    @discardableResult
    func dropPlayerItem(_ item: FormID?, count: Int32) -> String
}
