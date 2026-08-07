// Production conformer of `PapyrusWorldBridge` (issue #172): the object that
// owns the main-actor references a native is not allowed to hold itself.
//
// Ownership, so nothing here leaks: the store outlives the session and is held
// strongly; the world runtime is held weakly because it owns the native
// registry that owns this bridge; the reference source (`CellStreamer`) is
// held weakly because the same controller owns both.

import Foundation

@MainActor
final class PapyrusWorldStateBridge: PapyrusWorldBridge {
    let worldState: WorldStateStore
    /// Set immediately after the world runtime is built — it cannot be an init
    /// parameter, because the runtime is constructed with the native registry
    /// this bridge already lives inside.
    weak var world: PapyrusWorldRuntime?
    weak var references: (any PapyrusWorldReferenceSource)?
    /// Plugin GLOB defaults. Nil in a synthetic session, where only overrides
    /// already recorded in the store are visible.
    var globals: GlobalStore?
    /// Quest mutation API the `Quest` natives run through (issue #322). Nil in
    /// a session with no QUST index, where every quest native fails with
    /// `PapyrusQuestBridgeError.noQuestData` rather than inventing state.
    /// Conformance lives in `PapyrusWorldStateBridgeQuests.swift`.
    var questRuntime: QuestRuntime?
    /// Quests whose alias fill failed while their scripts were being attached
    /// at session wire-up (issue #183). Counted rather than thrown, because a
    /// quest that reads as running straight off its DNAM flag was never
    /// `Start`ed and so has no call to refuse; see `attachRunningQuestScripts`.
    var questAliasFillFailures = 0
    /// Game clock the five time globals project from, matching how every other
    /// consumer builds a `GlobalResolution`.
    var clockSource: (() -> GameClock?)?
    /// Master-list resolver for the FormIDs written inside decoded records —
    /// XLKR links and their keywords. Nil in a synthetic session, which falls
    /// back to the reference index.
    var formIDResolver: FormIDResolver?

    /// Lazily built reverse map for the global lookups, which are keyed by
    /// `ReferenceKey` on the Papyrus side and by `FormID` on the store side.
    private var globalFormIDsByKey: [ReferenceKey: FormID]?

    init(
        worldState: WorldStateStore,
        world: PapyrusWorldRuntime? = nil,
        references: (any PapyrusWorldReferenceSource)? = nil,
        globals: GlobalStore? = nil
    ) {
        self.worldState = worldState
        self.world = world
        self.references = references
        self.globals = globals
    }

    var playerKey: ReferenceKey {
        .player
    }

    // MARK: - Identity

    func referenceKey(for handle: PapyrusObjectHandle) -> ReferenceKey? {
        world?.referenceKey(for: handle)
    }

    func objectHandle(for key: ReferenceKey) -> PapyrusObjectHandle? {
        world?.objectHandle(for: key)
    }

    // MARK: - Reading

    func referenceState(for key: ReferenceKey) -> ReferenceState? {
        guard let entry = references?.referenceEntry(key: key) else { return nil }
        return worldState.resolvedState(for: entry)
    }

    /// Resolves through the session's master-list resolver first — the same one
    /// every streamed reference key came from, so the two always agree — and
    /// falls back to the reference index, which is what makes a synthetic
    /// session with no resolver work.
    ///
    /// Stated limitation: one resolver covers the session, so a FormID spelled
    /// by a plugin other than the one it was built for resolves against the
    /// wrong master list. That is the same single-resolver assumption the cell
    /// builder already makes, not a new one.
    func referenceKey(forFormID formID: FormID) -> ReferenceKey? {
        if let formIDResolver, let key = ReferenceKey.resolve(formID, using: formIDResolver) {
            return key
        }
        return references?.referenceEntry(formID: formID)?.key
    }

    func placedReference(for key: ReferenceKey) -> PlacedReference? {
        references?.referenceEntry(key: key)?.placedReference
    }

    func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        references?.cellLocation(of: key)
    }

    // MARK: - Writing

    @discardableResult
    func write(
        _ component: WorldStateComponentValue, for key: ReferenceKey
    ) -> Bool {
        let cell = cellLocation(of: key)
        switch component {
        case let .enableState(value):
            return worldState.set(value, for: key, in: cell)
        case let .transform(value):
            return worldState.set(value, for: key, in: cell)
        case let .activation(value):
            return worldState.set(value, for: key, in: cell)
        case let .deletion(value):
            return worldState.set(value, for: key, in: cell)
        case let .inventory(value):
            // No Papyrus native reaches this yet — `AddItem` and `RemoveItem`
            // land with the inventory natives (#178/#179) and will go through
            // `InventoryRuntime` so the accounting rules apply. Writing it
            // through the same seam anyway keeps the bridge total: a component
            // the VM can hold is a component the VM can store.
            return worldState.set(value, for: key, in: cell)
        case let .spawn(value):
            // Same reasoning: `PlaceAtMe` is a later milestone's native, and
            // when it arrives it writes this component. Attribution goes to the
            // spawn's own cell rather than to `cellLocation(of:)`, which cannot
            // answer for an object that is not in the world yet.
            return worldState.set(value, for: key, in: value.location)
        case let .quest(value):
            // Same reasoning again: the `Quest` natives are issue #322, and
            // when they arrive they go through `QuestRuntime` so the stage and
            // objective rules apply. A quest belongs to no cell, so this write
            // is unattributed rather than attributed to the caller's cell.
            return worldState.set(value, for: key)
        case let .questAliases(value):
            // Alias tables are written by `QuestRuntime` at quest start rather
            // than by any native — no script function replaces a whole table —
            // but the seam stays total, and a quest belongs to no cell here for
            // the same reason its state does.
            return worldState.set(value, for: key)
        case let .actorValues(value):
            // Same reasoning: `DamageActorValue` and `RestoreActorValue` are a
            // later milestone's natives, and when they arrive they go through
            // `ActorValueRuntime` so the clamping applies. An actor is a placed
            // reference, so this write is attributed to its cell.
            return worldState.set(value, for: key, in: cell)
        case let .death(value):
            // Same reasoning: `Kill` and `Resurrect` are a later milestone's
            // natives, and when they arrive they go through `RagdollRuntime` so
            // the death events are raised and the ragdoll is handed off. An
            // actor is a placed reference, so this write is attributed to its
            // cell.
            return worldState.set(value, for: key, in: cell)
        }
    }

    // MARK: - Globals

    func globalValue(for key: ReferenceKey) -> GlobalValue? {
        guard let globals, let id = globalFormID(for: key) else {
            return worldState.globalValue(for: key)
        }
        return worldState
            .globalResolution(defaults: globals, clock: clockSource?())
            .value(for: id)
    }

    /// A write with no GLOB record behind it — a synthetic session, or a key
    /// the loaded plugins do not define — keeps whatever type an existing
    /// override declared and otherwise treats the value as a float, rather
    /// than inventing a `short`/`long` rounding rule the plugin never stated.
    @discardableResult
    func setGlobal(_ raw: Float, for key: ReferenceKey) -> Bool {
        if let globals, let id = globalFormID(for: key) {
            return worldState.setGlobal(raw, formID: id, defaults: globals)
        }
        let type = worldState.globalValue(for: key)?.type ?? .float
        return worldState.setGlobal(raw, type: type, for: key)
    }

    private func globalFormID(for key: ReferenceKey) -> FormID? {
        if let globalFormIDsByKey {
            return globalFormIDsByKey[key]
        }
        var map: [ReferenceKey: FormID] = [:]
        for global in globals?.sortedGlobals() ?? [] {
            guard let globalKey = globals?.key(for: global.formID) else { continue }
            map[globalKey] = global.formID
        }
        globalFormIDsByKey = map
        return map[key]
    }

    // MARK: - Activation

    /// Records one activation and queues `OnActivate` on the target's scripts.
    ///
    /// The recursion cap is consulted first: a refused activation writes no
    /// state either, so a script pair activating each other cannot keep
    /// incrementing `activationCount` forever.
    @discardableResult
    func activate(
        _ target: ReferenceKey,
        by activator: ReferenceKey,
        togglesOpen: Bool
    ) -> PapyrusActivationOutcome {
        let queued = world?.queueOnActivate(target: target, activator: activator)
            ?? .none
        guard !queued.cappedByRecursion else { return queued }
        let current = worldState.component(ReferenceActivationState.self, for: target)
            ?? referenceState(for: target)?.activation
            ?? .untouched
        let recorded = write(
            current.activated(by: activator, togglesOpen: togglesOpen).erased,
            for: target
        )
        return PapyrusActivationOutcome(
            recorded: recorded,
            queuedEvents: queued.queuedEvents,
            cappedByRecursion: false
        )
    }

    // MARK: - Update timers

    func registerUpdateTimer(
        handle: PapyrusObjectHandle,
        slot: PapyrusUpdateTimerSlot,
        interval: Double
    ) {
        world?.registerUpdateTimer(handle: handle, slot: slot, interval: interval)
    }

    func unregisterUpdateTimers(
        handle: PapyrusObjectHandle,
        family: PapyrusUpdateTimerFamily
    ) {
        world?.unregisterUpdateTimers(handle: handle, family: family)
    }

    /// `CellStreamer.onInteraction` subscriber (issue #172): the player's
    /// use key becomes one recorded activation plus one `OnActivate` per
    /// script attached to the target.
    ///
    /// `InteractionEvent` carries a load-order-relative `FormID`, so the key
    /// comes from the streamer's decoded entry; an event for a reference no
    /// resident cell knows is dropped rather than recorded under a guessed
    /// identity. A door-style `open` action is what sets `togglesOpen`, which
    /// is how `ReferenceActivationState.isOpen` tracks doors and containers.
    @discardableResult
    func handleInteraction(_ event: InteractionEvent) -> PapyrusActivationOutcome {
        let interaction = event.target.interaction
        guard
            let entry = references?.referenceEntry(formID: interaction.reference)
        else { return .none }
        return activate(
            entry.key,
            by: playerKey,
            togglesOpen: interaction.action == .open
        )
    }
}
