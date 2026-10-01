// The seam other features read and write actor values through. `ActorValueRuntime`
// in OpenSkyActors conforms, and the composition root hands it to Magic,
// Progression, scripting, and the HUD as this protocol.

import OpenSkyGameData
import OpenSkyWorldState

/// The fixed step actor-value regeneration runs at, shared with the features that
/// advance beside it.
nonisolated public enum ActorValueStep {
    /// Simulation step regeneration advances in, matching the Papyrus VM's
    /// fixed step so that a frame drives both the same way. 1/60 s.
    public static let fixedStepSeconds = 1.0 / 60

    /// Most whole steps one `advance(delta:)` runs, so a multi-second stall
    /// cannot spend minutes regenerating in a single frame.
    public static let maximumStepsPerAdvance = 8
}

/// Reads and mutates actor values on top of a `WorldStateStore`.
@MainActor
public protocol ActorValueAccess {
    var store: WorldStateStore { get }

    var baselines: ActorValueBaselineResolver { get }

    /// `holder`'s maximums and regen rates, re-derived from plugin data.
    func baseline(of holder: ActorValueHolder) -> ActorValueBaseline

    /// `holder`'s effective maximums: the re-derived numbers plus base writes and
    /// the permanent and temporary modifiers. Damage is not included: it lowers the
    /// current value only (<https://ck.uesp.net/wiki/ModActorValue_-_Actor>).
    func maximums(of holder: ActorValueHolder) -> ActorValues

    /// `holder`'s current values.
    func current(of holder: ActorValueHolder) -> ActorValues

    /// `holder`'s current values as fractions of its maximums, which is the
    /// shape the HUD meters take.
    func fractions(of holder: ActorValueHolder) -> ActorValues

    /// Whether `holder` is at zero health. Ragdoll and death consume the flag; this layer
    /// does not act on it.
    func hasZeroHealth(_ holder: ActorValueHolder) -> Bool

    /// Takes `amount` off one of `holder`'s values, floored at zero. The first write
    /// stores the baseline, so 120 health minus 20 stores 100, not a delta of -20.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func damage(
        _ kind: ActorValueKind,
        by amount: Float,
        on holder: ActorValueHolder
    ) -> ActorValueState

    /// Sets one value outright, clamped to `0 ... maximum`. What a dev control
    /// and a console line drive; ordinary gameplay goes through `damage` and
    /// `restore`.
    ///
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func set(
        _ kind: ActorValueKind,
        to value: Float,
        on holder: ActorValueHolder
    ) -> ActorValueState

    /// Refills every value to its maximum.
    ///
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func restoreAll(on holder: ActorValueHolder) -> ActorValueState

    /// What `GetActorValue` reports for `index`: the stored current value for a
    /// primary, and base plus modifiers for everything else.
    ///
    /// - Returns: nil only for an index outside the vanilla table. Every value
    ///   the table names answers, falling back to its documented baseline.
    func value(at index: Int32, on holder: ActorValueHolder) -> Float?

    /// What `GetBaseActorValue` reports for `index`: the base value, which is
    /// what the records author plus whatever an explicit base write moved it
    /// by, and never a modifier.
    func baseValue(at index: Int32, on holder: ActorValueHolder) -> Float?

    /// `index`'s whole entry — base and all three modifiers — or nil for an
    /// index outside the table.
    func entry(at index: Int32, on holder: ActorValueHolder) -> ActorValueEntry?

    /// Every value `holder` has moved off its baseline, resolved against that
    /// baseline — the shape `ActorConditionState` and `PapyrusActorState`
    /// carry, so a snapshot answers exactly what a live read would.
    func resolvedEntries(of holder: ActorValueHolder) -> [Int32: ActorValueEntry]

    /// Takes `amount` off `index`, floored at zero. A primary loses current value;
    /// any other value uses the damage modifier, so a restore can undo it.
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func damage(at index: Int32, by amount: Float, on holder: ActorValueHolder) -> Bool

    /// Adds `amount` back to `index`, capped at its maximum for a primary and
    /// at "no damage" for everything else.
    ///
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func restore(at index: Int32, by amount: Float, on holder: ActorValueHolder) -> Bool

    /// Sets `index` outright: the current value for a primary, the base otherwise.
    /// This is the dev and console path; `setBase(at:to:on:)` is the script path.
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func setValue(at index: Int32, to value: Float, on holder: ActorValueHolder) -> Bool

    /// Sets `index`'s base value and keeps every modifier, like `SetActorValue`
    /// (<https://ck.uesp.net/wiki/SetActorValue_-_Actor>). Stored as an offset from
    /// the re-derived baseline, so a later level change still applies.
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func setBase(at index: Int32, to value: Float, on holder: ActorValueHolder) -> Bool

    /// Raises `index`'s base by `delta`, as a skill advance or attribute pick does.
    /// The increment stays on top of the re-derived value.
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func incrementBase(
        at index: Int32,
        by delta: Float,
        on holder: ActorValueHolder
    ) -> Bool

    /// Raises one of the eighteen skills' base by `delta`. A separate name, so a
    /// wrong index that is not a skill fails at the one call site that means a skill.
    /// - Returns: false for every index that is not one of the eighteen skills.
    @discardableResult
    func advanceSkill(
        at index: Int32,
        by delta: Float,
        on holder: ActorValueHolder
    ) -> Bool

    /// Adds `delta` to one of `index`'s modifier slots. Effects and `ModActorValue`
    /// write through this, primaries included.
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func addModifier(
        _ delta: Float,
        to modifier: ActorValueModifier,
        at index: Int32,
        on holder: ActorValueHolder
    ) -> Bool

    /// Sets one of `index`'s modifier slots outright.
    ///
    /// - Returns: false by the same rule `addModifier` answers false.
    @discardableResult
    func setModifier(
        _ value: Float,
        for modifier: ActorValueModifier,
        at index: Int32,
        on holder: ActorValueHolder
    ) -> Bool

    /// Forces `index`'s current value to `value` by moving its permanent modifier,
    /// as `ForceActorValue` documents: base 125 forced to 0 gives a modifier of -125
    /// (<https://ck.uesp.net/wiki/ForceActorValue_-_Actor>).
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func forceValue(at index: Int32, to value: Float, on holder: ActorValueHolder) -> Bool

    /// What one point of magic damage of `element`'s school is multiplied by:
    /// Resist Magic first, then the element's resistance, in UESP's order.
    /// - Parameter element: the MGEF's resistance value; nil still pays Resist Magic.
    /// - Returns: 1 when nothing resists, 0 when immune, above 1 for a weakness
    ///   (<https://en.uesp.net/wiki/Skyrim:Weakness_to_Fire>).
    func magicDamageMultiplier(
        element: Int32?,
        on holder: ActorValueHolder,
        settings: ActorResistanceSettings
    ) -> Float
}
