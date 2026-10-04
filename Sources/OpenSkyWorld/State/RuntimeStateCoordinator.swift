// World > Runtime State: reference mutations, save slots, game time, globals,
// and condition lists. A mutation records against no cell, which rebuilds every
// resident cell: correct, but broader than needed.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyWorldState

@MainActor
public final class RuntimeStateCoordinator {
    /// GLOB defaults of the loaded plugins. Nil without game data; a clock
    /// scrub then writes the renderer's clock directly.
    public private(set) var globalStore: GlobalStore?
    public private(set) var lastSaveOutcome = RuntimeStateSaveOutcome.none

    let worldState: WorldStateStore
    weak var world: (any RuntimeStateWorld)?

    /// The readout asks twice a second, so these are cached. Globals and music
    /// records do not change while the app runs; slots change only on save or load.
    var cachedSlotNames: [String]?
    /// The running save, load, or slot listing; one at a time.
    public private(set) var saveWork: Task<Void, Never>?
    private(set) var slotListing: Task<Void, Never>?
    var globalNamesByKey: [ReferenceKey: String]?
    var globalEditorIDs: [String]?
    var conditionSourceFormIDs: [String: FormID]?
    /// Accumulated across every evaluation, so the readout shows a running total.
    var conditionTally = ConditionTally()

    public init(store: WorldStateStore) {
        worldState = store
    }

    public func attach(world: any RuntimeStateWorld) {
        self.world = world
    }

    /// A global write hands weather and the clock fresh values instead of
    /// rebuilding cells. The five time globals write into the clock.
    public func attach(globals store: GlobalStore?) {
        globalStore = store
        globalNamesByKey = nil
        globalEditorIDs = nil
        world?.applyGlobalResolution(worldState.globalResolution(defaults: store), reroll: false)
        worldState.onTimeGlobalWrite = { [weak self] timeGlobal, value in
            self?.world?.projectTimeGlobal(timeGlobal, value: value)
        }
        worldState.onGlobalMutation = { [weak self] _ in
            guard let self else { return }
            world?.applyGlobalResolution(
                worldState.globalResolution(defaults: store), reroll: true
            )
        }
    }

    /// The reference a selector names. Only a resident reference resolves,
    /// because only it has a runtime entry to mutate.
    public func entry(for target: RuntimeStateTargetSelector) -> RuntimeReferenceEntry? {
        guard let world else { return nil }
        switch target {
        case .currentTarget:
            return world.crosshairReference.flatMap(world.referenceEntry(formID:))
        case let .formID(text):
            return RuntimeStateCore.parseFormID(text).flatMap(world.referenceEntry(formID:))
        }
    }

    /// Falls back to the bare FormID when the reference is not resident, so the
    /// readout never goes blank while the crosshair is on something.
    var currentTargetDescription: String? {
        guard let formID = world?.crosshairReference else { return nil }
        return world?.referenceEntry(formID: formID)?.key.description ?? formID.description
    }

    func globalNames() -> [ReferenceKey: String] {
        if let cached = globalNamesByKey {
            return cached
        }
        let names = RuntimeStateCore.globalNamesByKey(globalStore)
        globalNamesByKey = names
        return names
    }
}

extension RuntimeStateCoordinator: RuntimeStateControlProviding {
    public var runtimeStateSnapshot: RuntimeStateSnapshot {
        RuntimeStateSnapshot(
            residentReferenceCount: world?.residentReferenceCount ?? 0,
            dirtyReferenceCount: worldState.dirtyCount,
            journalTail: RuntimeStateCore.journalTail(
                entries: worldState.journalEntries,
                globalEntries: worldState.globalJournalEntries,
                names: globalNames()
            ),
            droppedJournalEntryCount: worldState.droppedJournalEntryCount
                + worldState.droppedGlobalJournalEntryCount,
            nextJournalSequence: worldState.nextJournalSequence,
            currentTargetDescription: currentTargetDescription,
            overriddenGlobalCount: worldState.overriddenGlobalCount
        )
    }

    /// A listing failure reads as "no slots": the list is a readout.
    /// Empty until the first listing arrives.
    public var runtimeStateSaveSlots: [String] {
        if cachedSlotNames == nil, slotListing == nil, let world {
            slotListing = Task {
                self.cachedSlotNames = await (try? world.saveSlots()) ?? []
                self.slotListing = nil
            }
        }
        return cachedSlotNames ?? []
    }

    @discardableResult
    public func setReferenceEnabled(_ enabled: Bool, target: RuntimeStateTargetSelector) -> Bool {
        guard let entry = entry(for: target) else { return false }
        return worldState.set(ReferenceEnableState(isEnabled: enabled), for: entry.key)
    }

    /// Starts from the resolved transform, so repeated presses accumulate.
    @discardableResult
    public func nudgeReferenceTransform(target: RuntimeStateTargetSelector) -> Bool {
        guard let entry = entry(for: target) else { return false }
        let current = worldState.resolvedState(for: entry).transform
        let moved = ReferenceTransformOverride(
            position: current.position + RuntimeStateTuning.transformNudge,
            rotation: current.rotation,
            scale: current.scale
        )
        return worldState.set(moved, for: entry.key)
    }

    @discardableResult
    public func resetReferenceState(target: RuntimeStateTargetSelector) -> Bool {
        guard let entry = entry(for: target) else { return false }
        return worldState.reset(entry.key)
    }

    public func resetAllReferenceState() {
        worldState.resetAll()
    }

    public func saveWorldState(slot: String) {
        runSaveOperation("save", slot: slot) { try await $0.saveSession(slot: slot) }
    }

    public func loadWorldState(slot: String) {
        runSaveOperation("load", slot: slot) { try await $0.loadSession(slot: slot) }
    }

    private func runSaveOperation(
        _ operation: String, slot: String,
        _ body: @escaping @MainActor (any RuntimeStateWorld) async throws -> Void
    ) {
        guard saveWork == nil else {
            lastSaveOutcome = .failed(
                operation: operation,
                message: "another save or load is running"
            )
            return
        }
        guard let world else {
            lastSaveOutcome = .failed(
                operation: operation,
                message: String(describing: RuntimeStateSessionError.noSession)
            )
            return
        }
        lastSaveOutcome = .running(operation: operation, slot: slot)
        saveWork = Task {
            do {
                try await body(world)
                self
                    .lastSaveOutcome = operation == "save" ? .saved(slot: slot) :
                    .loaded(slot: slot)
            } catch {
                self.lastSaveOutcome = .failed(
                    operation: operation,
                    message: String(describing: error)
                )
            }
            self.cachedSlotNames = nil
            self.saveWork = nil
        }
    }
}

nonisolated public enum RuntimeStateSessionError: Error, CustomStringConvertible {
    case noSession

    public var description: String {
        "No game session is attached."
    }
}
