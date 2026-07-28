// World > Runtime State live bridge (M10.1.5): connects the sidebar panel to
// the session's `WorldStateStore`, the resident `CellStreamer`, and the
// on-disk save slots.
//
// Everything here degrades to a stated non-answer rather than to a crash or a
// trap. No streamer means no resident references, so every mutation reports
// false and the readout shows zeroes; a missing install means the fingerprint
// cannot be built, which surfaces as a failed save outcome rather than as an
// exception. That matters because this panel is the milestone's verification
// surface: it has to stay legible on a machine where the game data moved.
//
// Mutations are recorded against no cell (`in: nil`). Resolving a reference to
// its `CellSceneLocation` would need an index the composition does not keep,
// and an unattributed mutation rebuilds every resident cell, which is correct —
// just broader than necessary.

import AppKit

/// State the runtime-state bridge owns. Stored on `GameViewController` because
/// extensions cannot add stored properties; nothing else writes it.
struct RuntimeStateBridgeState {
    var lastSaveOutcome = RuntimeStateSaveOutcome.none
    /// Slot directory, resolved once. Locating it can fail (an unwritable
    /// Application Support), and retrying every readout tick would hammer the
    /// filesystem for the same answer.
    var saveStore: OpenSkySaveStore?
    /// Plugin fingerprint, computed once per session. Building it parses every
    /// plugin header in the load order, which is far too expensive for a 2 Hz
    /// readout and cannot change while the app runs.
    var fingerprint: [SavePluginFingerprint]?
    /// Slot names, cached because the readout ticker asks twice a second.
    /// Invalidated by a save or a load, which are the only writes this app
    /// makes to that directory.
    var cachedSlotNames: [String]?
}

extension GameViewController: RuntimeStateControlProviding {
    /// App version stamped into a save's metadata. Read from the bundle so a
    /// released build records what wrote the file; the CLI-less test host has
    /// no such key, which is what the fallback covers.
    static var runtimeStateSaveAppVersion: String {
        let key = "CFBundleShortVersionString"
        return Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "unknown"
    }

    var runtimeStateSnapshot: RuntimeStateSnapshot {
        let tail = worldState.journalEntries.suffix(RuntimeStateSnapshot.journalTailLimit)
        return RuntimeStateSnapshot(
            residentReferenceCount: streamer?.residentReferenceCount ?? 0,
            dirtyReferenceCount: worldState.dirtyCount,
            journalTail: tail.map(Self.journalLine),
            droppedJournalEntryCount: worldState.droppedJournalEntryCount,
            nextJournalSequence: worldState.nextJournalSequence,
            currentTargetDescription: currentRuntimeStateTargetDescription
        )
    }

    var lastSaveOutcome: RuntimeStateSaveOutcome {
        runtimeState.lastSaveOutcome
    }

    var runtimeStateSaveSlots: [String] {
        if let cached = runtimeState.cachedSlotNames {
            return cached
        }
        // A listing failure is reported as "no slots": the slot list is a
        // readout, and the panel already has a place to state a real failure.
        let slots = (try? runtimeStateSaveStore().listSlots()) ?? []
        runtimeState.cachedSlotNames = slots
        return slots
    }

    // MARK: Mutations

    @discardableResult
    func setReferenceEnabled(_ enabled: Bool, target: RuntimeStateTargetSelector) -> Bool {
        guard let entry = runtimeStateEntry(for: target) else { return false }
        return worldState.set(ReferenceEnableState(isEnabled: enabled), for: entry.key)
    }

    /// Reads the reference's resolved transform rather than its plugin
    /// baseline, so repeated presses accumulate instead of each one landing the
    /// object back at baseline plus one nudge.
    @discardableResult
    func nudgeReferenceTransform(target: RuntimeStateTargetSelector) -> Bool {
        guard let entry = runtimeStateEntry(for: target) else { return false }
        let current = worldState.resolvedState(for: entry).transform
        let moved = ReferenceTransformOverride(
            position: current.position + RuntimeStateTuning.transformNudge,
            rotation: current.rotation,
            scale: current.scale
        )
        return worldState.set(moved, for: entry.key)
    }

    @discardableResult
    func resetReferenceState(target: RuntimeStateTargetSelector) -> Bool {
        guard let entry = runtimeStateEntry(for: target) else { return false }
        return worldState.reset(entry.key)
    }

    func resetAllReferenceState() {
        worldState.resetAll()
    }

    // MARK: Save and load

    func saveWorldState(slot: String) {
        do {
            let metadata = SaveCreationMetadata(
                creationTimestamp: UInt64(max(0, Date().timeIntervalSince1970)),
                appVersion: Self.runtimeStateSaveAppVersion
            )
            try runtimeStateSaveStore().save(
                snapshot: worldState.snapshot(),
                fingerprint: runtimeStatePluginFingerprint(),
                metadata: metadata,
                clock: renderer?.gameClock,
                toSlot: slot
            )
            runtimeState.lastSaveOutcome = .saved(slot: slot)
        } catch {
            runtimeState.lastSaveOutcome = .failed(
                operation: "save", message: String(describing: error)
            )
        }
        runtimeState.cachedSlotNames = nil
    }

    /// Verifies against the current fingerprint when one can be built. A
    /// missing install leaves it nil, which skips verification rather than
    /// blocking the load: the file's own contents are still decoded and
    /// checked, and refusing to read a save because the game moved would be
    /// the less useful failure.
    func loadWorldState(slot: String) {
        do {
            let file = try runtimeStateSaveStore().load(
                slot: slot, verifyingAgainst: try? runtimeStatePluginFingerprint()
            )
            worldState.restore(from: file.snapshot)
            // Absent CLOK chunk (a pre-clock save) restores the vanilla-start
            // clock; setting `gameClock` also resets the weather's
            // elapsed-hours mark so the date jump ages no weather.
            renderer?.gameClock = file.clock ?? GameClock()
            runtimeState.lastSaveOutcome = .loaded(slot: slot)
        } catch {
            runtimeState.lastSaveOutcome = .failed(
                operation: "load", message: String(describing: error)
            )
        }
        runtimeState.cachedSlotNames = nil
    }

    // MARK: Resolution

    /// The reference a selector names, or nil when nothing resolves it. Both
    /// cases go through the streamer's resident index: a reference that is not
    /// streamed in has no runtime entry to mutate.
    func runtimeStateEntry(
        for target: RuntimeStateTargetSelector
    ) -> RuntimeReferenceEntry? {
        guard let streamer else { return nil }
        switch target {
        case .currentTarget:
            guard let formID = hud.interactionTarget?.interaction.reference else { return nil }
            return streamer.referenceEntry(formID: formID)
        case let .formID(text):
            guard let formID = Self.parseRuntimeStateFormID(text) else { return nil }
            return streamer.referenceEntry(formID: formID)
        }
    }

    /// Parses the panel's raw text as hexadecimal, with an optional `0x`
    /// prefix. Returns nil for anything that is not a FormID rather than
    /// guessing, so a typo reports "no change" instead of mutating an
    /// unrelated object.
    static func parseRuntimeStateFormID(_ text: String) -> FormID? {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if digits.hasPrefix("0x") {
            digits.removeFirst(2)
        }
        guard !digits.isEmpty, digits.count <= 8, let raw = UInt32(digits, radix: 16) else {
            return nil
        }
        return FormID(raw)
    }

    /// The targeted reference's key, falling back to the bare FormID when the
    /// resident index cannot resolve it, so the readout never goes blank while
    /// the crosshair is plainly on something.
    private var currentRuntimeStateTargetDescription: String? {
        guard let target = hud.interactionTarget else { return nil }
        let formID = target.interaction.reference
        guard let entry = streamer?.referenceEntry(formID: formID) else {
            return formID.description
        }
        return entry.key.description
    }

    private func runtimeStateSaveStore() throws -> OpenSkySaveStore {
        if let cached = runtimeState.saveStore {
            return cached
        }
        let store = try OpenSkySaveStore.defaultStore()
        runtimeState.saveStore = store
        return store
    }

    private func runtimeStatePluginFingerprint() throws -> [SavePluginFingerprint] {
        if let cached = runtimeState.fingerprint {
            return cached
        }
        let fingerprint = try OpenSkySaveStore.fingerprint(forRoot: GameDataLocator.locate())
        runtimeState.fingerprint = fingerprint
        return fingerprint
    }

    /// One journal entry as a readout line. The journal has no formatter of its
    /// own because only this panel displays it; the shape is sequence, what
    /// happened, and to which reference.
    static func journalLine(_ entry: WorldStateJournalEntry) -> String {
        let verb = entry.isReset ? "reset" : "set"
        return "\(entry.sequence) \(verb) \(entry.kind.rawValue) \(entry.key.description)"
    }
}
