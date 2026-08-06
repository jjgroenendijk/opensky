// The seam between nonisolated Papyrus natives and the main-actor world
// (issue #172).
//
// Three types live here and the split is deliberate:
//
// * `PapyrusWorldBridge` is the `@MainActor` protocol every world operation a
//   native may perform is declared on. Its production conformer is
//   `PapyrusWorldStateBridge`; tests conform their own.
// * `PapyrusWorldAccess` is the nonisolated façade a native body actually
//   holds, reached as `context.world`. Each method is a one-line hop onto the
//   main actor.
// * `PapyrusWorldReferenceSource` is what the bridge asks for decoded
//   references and their resident cell. `CellStreamer` conforms in the app; a
//   synthetic index conforms in tests, so natives are testable with no GPU and
//   no streamer.
//
// Concurrency, stated plainly: `WorldStateStore` and `PapyrusWorldRuntime` are
// `@MainActor`, while `PapyrusNativeFunction.Body` is nonisolated and
// `@Sendable`. Native bodies are nevertheless only ever run synchronously from
// `PapyrusWorldRuntime`'s tick, which is on the main actor, so
// `PapyrusWorldAccess` asserts that with `MainActor.assumeIsolated` rather than
// hiding the mismatch behind `@unchecked Sendable` or a global. A headless
// runtime leaves `PapyrusNativeContext.world` nil and never reaches this file,
// which is why every access is optional at the call site.

import Foundation

/// What one activation did, returned by both
/// `PapyrusWorldBridge.activate(_:by:togglesOpen:)` and
/// `PapyrusWorldRuntime.queueOnActivate(target:activator:)`. The queue-only
/// caller always reports `recorded == false`, because it writes no state.
nonisolated struct PapyrusActivationOutcome: Equatable, Sendable {
    /// True when the `ReferenceActivationState` write changed stored state.
    let recorded: Bool
    /// `OnActivate` events enqueued on the target's script instances.
    let queuedEvents: Int
    /// True when the recursion cap refused to queue anything.
    let cappedByRecursion: Bool

    static let none = PapyrusActivationOutcome(
        recorded: false, queuedEvents: 0, cappedByRecursion: false
    )
}

/// Decoded references and their resident cell, as the bridge needs them.
///
/// Nonisolated because `CellStreamer` is: the bridge only ever calls it from
/// the main actor, on the same thread that drives `draw(in:)`.
nonisolated protocol PapyrusWorldReferenceSource: AnyObject {
    func referenceEntry(formID: FormID) -> RuntimeReferenceEntry?
    func referenceEntry(key: ReferenceKey) -> RuntimeReferenceEntry?
    /// Cell the reference is currently resident in, or nil when nothing
    /// resident holds it. A write attributed to a cell rebuilds that cell
    /// alone; nil rebuilds every resident cell.
    func cellLocation(of key: ReferenceKey) -> CellSceneLocation?
}

/// Every world operation a Papyrus native is allowed to perform.
///
/// Issue #172 builds this seam; the natives that plug into it are `Enable`,
/// `Disable`, `IsEnabled`, `GetPositionX`/`Y`/`Z`, `SetPosition`, `Delete`,
/// `Activate`, `GetLinkedRef`, `GlobalVariable.GetValue`/`SetValue`, and
/// `Game.GetPlayer`. Nothing here writes around `WorldStateStore`: every
/// mutation is one `set(_:for:in:)` or `setGlobal(_:formID:defaults:)` call,
/// so the journal, the dirty counts, and the save see it.
/// The quest operations are declared separately, in
/// `PapyrusWorldQuestBridge.swift` (issue #322), and refined in here so a
/// native reaches all of it through the one `context.world` façade.
@MainActor
protocol PapyrusWorldBridge: PapyrusWorldQuestBridge {
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

    /// Cell `key` is resident in, for mutation attribution.
    func cellLocation(of key: ReferenceKey) -> CellSceneLocation?

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

    /// Arms one update-timer slot on the script instance behind `handle`
    /// (issue #277). A handle with no script instance behind it is a no-op.
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

/// Nonisolated façade over a `PapyrusWorldBridge`, held by
/// `PapyrusNativeContext.world` and called from native bodies.
///
/// Every method mirrors the protocol one-for-one and hops with
/// `MainActor.assumeIsolated`, which is an assertion, not a suppression: it
/// traps if a native ever runs off the main actor, and only a world-aware
/// runtime installs one of these.
nonisolated final class PapyrusWorldAccess: Sendable {
    /// Internal rather than private so the quest hops can live in
    /// `PapyrusWorldQuestBridge.swift` beside the protocol they mirror. Only
    /// this type's own extensions touch it.
    let bridge: any PapyrusWorldBridge

    init(bridge: any PapyrusWorldBridge) {
        self.bridge = bridge
    }

    var playerKey: ReferenceKey {
        MainActor.assumeIsolated { bridge.playerKey }
    }

    func referenceKey(for handle: PapyrusObjectHandle) -> ReferenceKey? {
        MainActor.assumeIsolated { bridge.referenceKey(for: handle) }
    }

    func objectHandle(for key: ReferenceKey) -> PapyrusObjectHandle? {
        MainActor.assumeIsolated { bridge.objectHandle(for: key) }
    }

    func referenceState(for key: ReferenceKey) -> ReferenceState? {
        MainActor.assumeIsolated { bridge.referenceState(for: key) }
    }

    func referenceKey(forFormID formID: FormID) -> ReferenceKey? {
        MainActor.assumeIsolated { bridge.referenceKey(forFormID: formID) }
    }

    func placedReference(for key: ReferenceKey) -> PlacedReference? {
        MainActor.assumeIsolated { bridge.placedReference(for: key) }
    }

    func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        MainActor.assumeIsolated { bridge.cellLocation(of: key) }
    }

    @discardableResult
    func write(
        _ component: WorldStateComponentValue, for key: ReferenceKey
    ) -> Bool {
        MainActor.assumeIsolated { bridge.write(component, for: key) }
    }

    func globalValue(for key: ReferenceKey) -> GlobalValue? {
        MainActor.assumeIsolated { bridge.globalValue(for: key) }
    }

    @discardableResult
    func setGlobal(_ raw: Float, for key: ReferenceKey) -> Bool {
        MainActor.assumeIsolated { bridge.setGlobal(raw, for: key) }
    }

    @discardableResult
    func activate(
        _ target: ReferenceKey,
        by activator: ReferenceKey,
        togglesOpen: Bool
    ) -> PapyrusActivationOutcome {
        MainActor.assumeIsolated {
            bridge.activate(target, by: activator, togglesOpen: togglesOpen)
        }
    }

    func registerUpdateTimer(
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

    func unregisterUpdateTimers(
        handle: PapyrusObjectHandle,
        family: PapyrusUpdateTimerFamily
    ) {
        MainActor.assumeIsolated {
            bridge.unregisterUpdateTimers(handle: handle, family: family)
        }
    }
}
