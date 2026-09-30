// The seam between nonisolated Papyrus natives and the main-actor world.
// `PapyrusWorldBridge` is the `@MainActor` protocol (`PapyrusWorldStateBridge` in
// production). `PapyrusWorldAccess` is the nonisolated facade natives hold; it
// hops with `MainActor.assumeIsolated`, since natives only run from the
// main-actor tick. `PapyrusWorldReferenceSource` supplies references.

import Foundation
import OpenSkyFormatsESM
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

/// Nonisolated facade over a `PapyrusWorldBridge`, held by
/// `PapyrusNativeContext.world`. Each method hops with `MainActor.assumeIsolated`,
/// which traps if a native runs off the main actor.
nonisolated public final class PapyrusWorldAccess: Sendable {
    /// Internal rather than private so the quest hops can live in
    /// `PapyrusWorldQuestBridge.swift` beside the protocol they mirror. Only
    /// this type's own extensions touch it.
    public let bridge: any PapyrusWorldBridge

    public init(bridge: any PapyrusWorldBridge) {
        self.bridge = bridge
    }

    public var playerKey: ReferenceKey {
        MainActor.assumeIsolated { bridge.playerKey }
    }

    public func referenceKey(for handle: PapyrusObjectHandle) -> ReferenceKey? {
        MainActor.assumeIsolated { bridge.referenceKey(for: handle) }
    }

    public func objectHandle(for key: ReferenceKey) -> PapyrusObjectHandle? {
        MainActor.assumeIsolated { bridge.objectHandle(for: key) }
    }

    public func referenceState(for key: ReferenceKey) -> ReferenceState? {
        MainActor.assumeIsolated { bridge.referenceState(for: key) }
    }

    public func referenceKey(forFormID formID: FormID) -> ReferenceKey? {
        MainActor.assumeIsolated { bridge.referenceKey(forFormID: formID) }
    }

    public func placedReference(for key: ReferenceKey) -> PlacedReference? {
        MainActor.assumeIsolated { bridge.placedReference(for: key) }
    }

    @discardableResult
    public func write(
        _ component: WorldStateComponentValue, for key: ReferenceKey
    ) -> Bool {
        MainActor.assumeIsolated { bridge.write(component, for: key) }
    }

    public func globalValue(for key: ReferenceKey) -> GlobalValue? {
        MainActor.assumeIsolated { bridge.globalValue(for: key) }
    }

    @discardableResult
    public func setGlobal(_ raw: Float, for key: ReferenceKey) -> Bool {
        MainActor.assumeIsolated { bridge.setGlobal(raw, for: key) }
    }

    @discardableResult
    public func activate(
        _ target: ReferenceKey,
        by activator: ReferenceKey,
        togglesOpen: Bool
    ) -> PapyrusActivationOutcome {
        MainActor.assumeIsolated {
            bridge.activate(target, by: activator, togglesOpen: togglesOpen)
        }
    }

    public func registerUpdateTimer(
        handle: PapyrusObjectHandle,
        slot: PapyrusUpdateTimerSlot,
        interval: Double
    ) {
        MainActor.assumeIsolated {
            bridge.registerUpdateTimer(
                handle: handle, slot: slot, interval: interval
            )
        }
    }

    public func unregisterUpdateTimers(
        handle: PapyrusObjectHandle,
        family: PapyrusUpdateTimerFamily
    ) {
        MainActor.assumeIsolated {
            bridge.unregisterUpdateTimers(handle: handle, family: family)
        }
    }
}
