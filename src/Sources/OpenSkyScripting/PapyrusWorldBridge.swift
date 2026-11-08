// The seam between Papyrus natives and the world. Natives and the world both run
// on the main actor. `PapyrusWorldStateBridge` is the production conformer, and
// `PapyrusWorldReferenceSource` supplies references.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyInventoryInterface
public import OpenSkyScriptingInterface
public import OpenSkyWorldState

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

    /// The decoded REFR behind `key`.
    func placedReference(for key: ReferenceKey) -> PlacedReference?

    /// The `XLKR` links of the placed reference or placed actor behind `key`.
    func linkedReferences(of key: ReferenceKey) -> [PlacedReference.LinkedReference]

    /// The reference's XLOC with this session's lock delta on top, or nil when it has
    /// neither.
    func lockState(for key: ReferenceKey) -> ReferenceLockState?

    /// How many actors stand in the trigger volume of `key`.
    func triggerObjectCount(for key: ReferenceKey) -> Int

    /// The direct entries of the FLST `key`, nested lists unexpanded; nil entries are null
    /// FormIDs. Nil when `key` is no form list or the session has no FLST data.
    func formListEntries(of key: ReferenceKey) -> [ReferenceKey?]?

    /// Whether the `KWDA` of `form`, or of its base when it is placed, holds `keyword`.
    /// Nil without keyword data or when either form is unknown.
    func formHasKeyword(_ form: ReferenceKey, keyword: ReferenceKey) -> Bool?

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

    /// The base form of a placed reference or a placed actor.
    func baseObject(of key: ReferenceKey) -> FormID?
}

extension PapyrusWorldBridge {
    public func linkedReferences(of key: ReferenceKey) -> [PlacedReference.LinkedReference] {
        placedReference(for: key)?.linkedReferences ?? []
    }
}
