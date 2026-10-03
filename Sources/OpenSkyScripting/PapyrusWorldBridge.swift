// The seam between Papyrus natives and the world. Natives and the world both run
// on the main actor. `PapyrusWorldStateBridge` is the production conformer, and
// `PapyrusWorldReferenceSource` supplies references.

import Foundation
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyScriptingInterface
import OpenSkyWorldState

/// What one activation did, returned by both
/// `PapyrusWorldBridge.activate(_:by:togglesOpen:)` and
/// `PapyrusWorldRuntime.queueOnActivate(target:activator:)`. The queue-only
/// caller always reports `recorded == false`, because it writes no state.
nonisolated public struct PapyrusActivationOutcome: Equatable, Sendable {
    /// True when the `ReferenceActivationState` write changed stored state.
    public let recorded: Bool
    /// `OnActivate` events enqueued on the target's script instances.
    public let queuedEvents: Int
    /// True when the recursion cap refused to queue anything.
    public let cappedByRecursion: Bool

    public static let none = PapyrusActivationOutcome(
        recorded: false, queuedEvents: 0, cappedByRecursion: false
    )
}

/// Every world operation a Papyrus native may perform. Every write is one
/// `set(_:for:in:)` or `setGlobal(_:formID:defaults:)` call. It refines the quest,
/// actor, magic, crime, faction, and guard bridges, and the barter operation, so
/// natives reach everything through `context.world`.
@MainActor
public protocol PapyrusWorldBridge:
    PapyrusWorldQuestBridge, PapyrusWorldActorBridge, PapyrusWorldMagicBridge,
    PapyrusWorldCrimeBridge, PapyrusWorldFactionBridge, PapyrusWorldGuardBridge,
    PapyrusWorldBarterBridge
{
    /// Session-stable identity of the player; see `ReferenceKey.player`.
    var playerKey: ReferenceKey { get }

    /// World identity behind a `PapyrusNativeCall.receiver` or an object
    /// argument, or nil for a handle with no world meaning.
    func referenceKey(for handle: PapyrusObjectHandle) -> ReferenceKey?

    /// A handle for `key`, stable for the session: the live script instance's
    /// handle when the reference carries scripts, an opaque one otherwise. Nil
    /// only when no world runtime is attached.
    func objectHandle(for key: ReferenceKey) -> PapyrusObjectHandle?

    /// Plugin baseline with this session's deltas applied, or nil when no
    /// resident cell knows the reference.
    func referenceState(for key: ReferenceKey) -> ReferenceState?

    /// World identity of a FormID read back out of a decoded record.
    ///
    /// `GetLinkedRef` needs this in both directions of one comparison: XLKR
    /// stores its linked reference and its keyword as load-order-relative
    /// FormIDs, while everything on the Papyrus side is already a
    /// `ReferenceKey`. Nil when nothing in this session can name the FormID.
    func referenceKey(forFormID formID: FormID) -> ReferenceKey?

    /// The decoded REFR behind `key`, which is where linked references live.
    func placedReference(for key: ReferenceKey) -> PlacedReference?

    /// The reference's XLOC with this session's lock delta on top, or nil when it has
    /// neither.
    func lockState(for key: ReferenceKey) -> ReferenceLockState?

    /// How many actors stand in the trigger volume of `key`.
    func triggerObjectCount(for key: ReferenceKey) -> Int

    /// Writes one component through `WorldStateStore.set(_:for:in:)`,
    /// attributing it to the reference's resident cell when there is one.
    ///
    /// - Returns: true when stored state changed.
    @discardableResult
    func write(_ component: WorldStateComponentValue, for key: ReferenceKey) -> Bool

    /// Effective value of a global: this session's override, else the plugin
    /// default, else nil when nothing defines it.
    func globalValue(for key: ReferenceKey) -> GlobalValue?

    /// Writes a global, coerced onto its declared type.
    ///
    /// - Returns: true when stored state changed.
    @discardableResult
    func setGlobal(_ raw: Float, for key: ReferenceKey) -> Bool

    /// Records an activation on `target` and queues its `OnActivate`.
    ///
    /// This is the whole of the `Activate` native's world effect: it never
    /// re-runs the interaction raycast and never moves a door. Recursion is
    /// capped by `PapyrusWorldRuntime.maximumActivationDepth` and a refused
    /// activation is tallied.
    @discardableResult
    func activate(
        _ target: ReferenceKey,
        by activator: ReferenceKey,
        togglesOpen: Bool
    ) -> PapyrusActivationOutcome

    /// Arms one update-timer slot on the script instance behind `handle`. A handle
    /// with no instance is a no-op.
    func registerUpdateTimer(
        handle: PapyrusObjectHandle,
        slot: PapyrusUpdateTimerSlot,
        interval: Double
    )

    /// Clears both of `family`'s timer slots on the instance behind `handle`.
    func unregisterUpdateTimers(
        handle: PapyrusObjectHandle,
        family: PapyrusUpdateTimerFamily
    )
}
