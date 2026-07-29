// Recording double for the World > Runtime State seam, shared by every panel
// suite and by the destination-registry satellite.
//
// It lives in its own file rather than inside `RuntimeStatePanelTests` because
// the M10.2 surfaces (clock, globals, conditions) roughly doubled its size and
// the parent suite is near the repo file-length limit. Stored properties cannot
// live in an extension, so splitting it out was the only way to keep the fake
// as one type.
//
// It records what the panel asked the engine to do so a test can assert on the
// selector, slot, editor ID or condition source each control carried, rather
// than on rendered text alone.

import AppKit
@testable import opensky

/// Sends a control's action the way a click would, so a test drives the panel
/// through the same path AppKit does.
@MainActor
func sendRuntimeStateControl(_ control: NSControl) {
    control.sendAction(control.action, to: control.target)
}

/// Depth-first search for a readout label's text by accessibility identifier.
///
/// Reading a readout back by id is what pins the id contract in this repo:
/// `make test-ui` is blocked on this machine (docs/tools/environment.md), so
/// these unit tests are the evidence that the UI-test API exists and carries
/// the value it claims.
@MainActor
func runtimeStateReadout(_ identifier: String, in view: NSView) -> String? {
    if view.accessibilityIdentifier() == identifier, let field = view as? NSTextField {
        return field.stringValue
    }
    for subview in view.subviews {
        if let found = runtimeStateReadout(identifier, in: subview) {
            return found
        }
    }
    return nil
}

@MainActor
final class FakeRuntimeStateProvider: RuntimeStateControlProviding {
    var runtimeStateSnapshot = RuntimeStateSnapshot.empty
    var lastSaveOutcome = RuntimeStateSaveOutcome.none
    var runtimeStateSaveSlots: [String] = []

    /// Every enable/disable the panel requested, in order.
    private(set) var enableCalls: [(enabled: Bool, target: RuntimeStateTargetSelector)] = []
    private(set) var nudgeCalls: [RuntimeStateTargetSelector] = []
    private(set) var resetCalls: [RuntimeStateTargetSelector] = []
    private(set) var resetAllCount = 0
    private(set) var savedSlots: [String] = []
    private(set) var loadedSlots: [String] = []

    /// What the next mutation reports back; false is the "could not resolve the
    /// reference" path the readout must state rather than swallow.
    var mutationSucceeds = true

    func setReferenceEnabled(_ enabled: Bool, target: RuntimeStateTargetSelector) -> Bool {
        enableCalls.append((enabled, target))
        return mutationSucceeds
    }

    func nudgeReferenceTransform(target: RuntimeStateTargetSelector) -> Bool {
        nudgeCalls.append(target)
        return mutationSucceeds
    }

    func resetReferenceState(target: RuntimeStateTargetSelector) -> Bool {
        resetCalls.append(target)
        return mutationSucceeds
    }

    /// Mirrors the engine: dropping every delta leaves nothing dirty, which is
    /// what clears the destination's override indicator.
    func resetAllReferenceState() {
        resetAllCount += 1
        runtimeStateSnapshot = Self.withCounts(
            runtimeStateSnapshot, dirty: 0,
            globals: runtimeStateSnapshot.overriddenGlobalCount
        )
    }

    func saveWorldState(slot: String) {
        savedSlots.append(slot)
        lastSaveOutcome = .saved(slot: slot)
    }

    func loadWorldState(slot: String) {
        loadedSlots.append(slot)
        lastSaveOutcome = .loaded(slot: slot)
    }

    // MARK: Game time

    /// One recorded calendar scrub. A struct rather than a tuple: three
    /// members is past the tuple cap the repo lints for.
    struct DateCall: Equatable {
        let day: Int
        let month: Int
        let year: Int
    }

    var runtimeStateClock = RuntimeStateClockSnapshot.empty
    private(set) var hourCalls: [Float] = []
    private(set) var dateCalls: [DateCall] = []
    private(set) var timescaleCalls: [Float] = []
    /// False is the "no TimeScale global is loaded" path.
    var timescaleWriteSucceeds = true

    func setGameClockHour(_ hour: Float) {
        hourCalls.append(hour)
        runtimeStateClock = RuntimeStateClockSnapshot(
            clock: GameClock(
                year: runtimeStateClock.year, month: runtimeStateClock.month,
                day: runtimeStateClock.day, hour: hour
            ),
            timescale: runtimeStateClock.timescale,
            isPaused: runtimeStateClock.isPaused
        )
    }

    func setGameClockDate(day: Int, month: Int, year: Int) {
        dateCalls.append(DateCall(day: day, month: month, year: year))
        runtimeStateClock = RuntimeStateClockSnapshot(
            clock: GameClock(
                year: year, month: month, day: day, hour: runtimeStateClock.hourOfDay
            ),
            timescale: runtimeStateClock.timescale,
            isPaused: runtimeStateClock.isPaused
        )
    }

    @discardableResult
    func setGameTimescale(_ timescale: Float) -> Bool {
        timescaleCalls.append(timescale)
        guard timescaleWriteSucceeds else { return false }
        runtimeStateClock = RuntimeStateClockSnapshot(
            clock: GameClock(
                year: runtimeStateClock.year, month: runtimeStateClock.month,
                day: runtimeStateClock.day, hour: runtimeStateClock.hourOfDay
            ),
            timescale: timescale,
            isPaused: runtimeStateClock.isPaused
        )
        return true
    }

    // MARK: Global variables

    var runtimeStateGlobalEditorIDs: [String] = []
    /// Editor ID (lowercased, as `GlobalStore` matches) to the sample the panel
    /// reads back.
    var globals: [String: RuntimeStateGlobalSnapshot] = [:]
    private(set) var globalWrites: [(editorID: String, value: Float)] = []
    private(set) var globalResets: [String] = []
    private(set) var resetAllGlobalsCount = 0

    func runtimeStateGlobal(editorID: String) -> RuntimeStateGlobalSnapshot? {
        globals[editorID.lowercased()]
    }

    @discardableResult
    func setGlobalValue(_ value: Float, editorID: String) -> Bool {
        globalWrites.append((editorID, value))
        guard let existing = globals[editorID.lowercased()] else { return false }
        globals[editorID.lowercased()] = RuntimeStateGlobalSnapshot(
            editorID: existing.editorID,
            formIDText: existing.formIDText,
            typeName: existing.typeName,
            defaultValue: existing.defaultValue,
            currentValue: value,
            isOverridden: true,
            isConstant: existing.isConstant
        )
        runtimeStateSnapshot = Self.withCounts(
            runtimeStateSnapshot,
            dirty: runtimeStateSnapshot.dirtyReferenceCount,
            globals: globals.values.count(where: \.isOverridden)
        )
        return true
    }

    @discardableResult
    func resetGlobalValue(editorID: String) -> Bool {
        globalResets.append(editorID)
        guard let existing = globals[editorID.lowercased()], existing.isOverridden else {
            return false
        }
        globals[editorID.lowercased()] = RuntimeStateGlobalSnapshot(
            editorID: existing.editorID,
            formIDText: existing.formIDText,
            typeName: existing.typeName,
            defaultValue: existing.defaultValue,
            currentValue: existing.defaultValue,
            isOverridden: false,
            isConstant: existing.isConstant
        )
        runtimeStateSnapshot = Self.withCounts(
            runtimeStateSnapshot,
            dirty: runtimeStateSnapshot.dirtyReferenceCount,
            globals: globals.values.count(where: \.isOverridden)
        )
        return true
    }

    func resetAllGlobalOverrides() {
        resetAllGlobalsCount += 1
        for (key, existing) in globals {
            globals[key] = RuntimeStateGlobalSnapshot(
                editorID: existing.editorID,
                formIDText: existing.formIDText,
                typeName: existing.typeName,
                defaultValue: existing.defaultValue,
                currentValue: existing.defaultValue,
                isOverridden: false,
                isConstant: existing.isConstant
            )
        }
        runtimeStateSnapshot = Self.withCounts(
            runtimeStateSnapshot, dirty: runtimeStateSnapshot.dirtyReferenceCount, globals: 0
        )
    }

    // MARK: Conditions

    var runtimeStateConditionSources: [String] = []
    /// Report handed back for a named source; anything else reports a stated
    /// non-answer, exactly as the live bridge does.
    var conditionReports: [String: RuntimeStateConditionReport] = [:]
    private(set) var evaluatedSources: [String] = []

    func evaluateConditions(source: String) -> RuntimeStateConditionReport {
        evaluatedSources.append(source)
        return conditionReports[source]
            ?? .unavailable(source: source, message: "No condition list named \(source).")
    }

    /// Rebuilds a snapshot with new counts, keeping everything else, because
    /// `RuntimeStateSnapshot` is immutable by design.
    private static func withCounts(
        _ snapshot: RuntimeStateSnapshot, dirty: Int, globals: Int
    ) -> RuntimeStateSnapshot {
        RuntimeStateSnapshot(
            residentReferenceCount: snapshot.residentReferenceCount,
            dirtyReferenceCount: dirty,
            journalTail: snapshot.journalTail,
            droppedJournalEntryCount: snapshot.droppedJournalEntryCount,
            nextJournalSequence: snapshot.nextJournalSequence,
            currentTargetDescription: snapshot.currentTargetDescription,
            overriddenGlobalCount: globals
        )
    }
}
