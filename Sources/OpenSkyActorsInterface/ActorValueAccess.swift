// The seam other features read and write actor values through. `ActorValueRuntime`
// in OpenSkyActors conforms, and the composition root hands it to Magic,
// Progression, scripting, and the HUD as this protocol.

import OpenSkyFormatsESM
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

    /// `holder`'s effective state: its runtime component when it has one, a
    /// full baseline when it does not.
    func state(of holder: ActorValueHolder) -> ActorValueState

    /// `holder`'s effective maximums: the re-derived numbers, plus whatever an
    /// explicit base write moved them by, plus the permanent and temporary
    /// modifiers a script or a magic effect put on them (issue #496, item 20.3).
    ///
    /// The derived part is re-read every time, so a level change or a reordered
    /// load order moves it and the session's own offsets ride on top unchanged.
    ///
    /// Damage is deliberately not in here. "ModActorValue is distinct from
    /// DamageActorValue because it adjusts the maximum value for the AV, while
    /// DamageActorValue or RestoreActorValue only adjust the current value"
    /// (<https://ck.uesp.net/wiki/ModActorValue_-_Actor>), and a primary's
    /// damage is the drop in its stored current value rather than a slot.
    func maximums(of holder: ActorValueHolder) -> ActorValues

    /// Whether `holder` has been touched at runtime, as opposed to still
    /// reading a full baseline.
    func hasRuntimeState(_ holder: ActorValueHolder) -> Bool

    /// `holder`'s current values.
    func current(of holder: ActorValueHolder) -> ActorValues

    /// `holder`'s current values as fractions of its maximums, which is the
    /// shape the HUD meters take.
    func fractions(of holder: ActorValueHolder) -> ActorValues

    /// Whether `holder` is at zero health. The flag item 15.6 consumes; this
    /// layer does not act on it.
    func hasZeroHealth(_ holder: ActorValueHolder) -> Bool

    /// Takes `amount` off one of `holder`'s values, floored at zero.
    ///
    /// The first mutation materializes the baseline into the component, so an
    /// actor with 120 maximum health that takes 20 damage ends up with a
    /// component holding 100 rather than a delta holding -20.
    ///
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func damage(
        _ kind: ActorValueKind,
        by amount: Float,
        on holder: ActorValueHolder
    ) -> ActorValueState

    /// Adds `amount` to one of `holder`'s values, capped at its maximum.
    ///
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func restore(
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

    /// Advances regeneration by exactly one fixed step for every holder in
    /// `holders`.
    ///
    /// Deterministic in two senses the acceptance gate cares about. The order
    /// is the caller's `ReferenceKey` order — `regeneration(over:)` sorts, so a
    /// set of actors regenerates identically whichever order they were
    /// collected in. And the amount is a pure function of the step and the
    /// baseline, with no accumulated float drift per actor: each step adds
    /// `maximum * percent / 100 * step`.
    ///
    /// Health does not regenerate at zero. An actor at zero health is dead or
    /// in bleedout, and both are 15.6's to decide; silently healing one back to
    /// life here would make that decision on 15.6's behalf.
    ///
    /// - Returns: the holders whose stored state actually changed.
    @discardableResult
    func stepRegeneration(over holders: [ActorValueHolder]) -> [ActorValueHolder]

    /// Accumulates a wall delta and runs whole fixed steps only, capped at
    /// `maximumStepsPerAdvance`; the remainder carries in `accumulator`.
    ///
    /// A zero delta advances nothing, regenerates nothing, and is safe to call
    /// every frame — the established menu-pause rule, which reaches this layer
    /// as delta 0 exactly as it reaches the Papyrus VM. A negative or
    /// non-finite delta is treated the same way rather than run backwards.
    ///
    /// The accumulator is the caller's, not the runtime's, because this type is
    /// a struct over a shared store: two of them may exist at once and a
    /// per-instance accumulator would silently split the simulation in half.
    ///
    /// - Returns: how many whole steps ran.
    @discardableResult
    func advance(
        delta: Float,
        accumulator: inout Double,
        over holders: [ActorValueHolder]
    ) -> Int

    /// Drops `holder`'s runtime state, so it re-derives a full baseline again.
    /// The component-level counterpart of `WorldStateStore.reset(_:)`.
    ///
    /// - Returns: true when runtime state was actually removed.
    @discardableResult
    func reset(_ holder: ActorValueHolder) -> Bool

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

    /// What `GetActorValuePercentage` reports: the current value over the
    /// maximum, clamped to 0 ... 1.
    ///
    /// A primary divides by its effective maximum rather than by its base,
    /// because that is the number its bar is drawn against and a fortified
    /// actor at full health is at full health. Every other value has no
    /// separate maximum, so its base is the ceiling.
    ///
    /// A zero or negative denominator reads as 0 rather than dividing, which is
    /// the rule `ActorValues.fractions(of:)` already applies to the HUD meters.
    func fraction(at index: Int32, on holder: ActorValueHolder) -> Float?

    /// `index`'s whole entry — base and all three modifiers — or nil for an
    /// index outside the table.
    func entry(at index: Int32, on holder: ActorValueHolder) -> ActorValueEntry?

    /// Every value `holder` has moved off its baseline, resolved against that
    /// baseline — the shape `ActorConditionState` and `PapyrusActorState`
    /// carry, so a snapshot answers exactly what a live read would.
    func resolvedEntries(of holder: ActorValueHolder) -> [Int32: ActorValueEntry]

    /// Takes `amount` off `index`, floored at zero.
    ///
    /// A primary takes it off its current value; every other actor value takes
    /// it through the damage modifier, so its base survives the blow and a
    /// later restore can undo exactly what was done.
    ///
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func damage(at index: Int32, by amount: Float, on holder: ActorValueHolder) -> Bool

    /// Adds `amount` back to `index`, capped at its maximum for a primary and
    /// at "no damage" for everything else.
    ///
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func restore(at index: Int32, by amount: Float, on holder: ActorValueHolder) -> Bool

    /// Sets `index` outright: the current value for a primary, and the base
    /// value for everything else.
    ///
    /// The dev-control and console path, which is why a primary lands on the
    /// current value here: a gate that asks for exactly 40 health means the
    /// bar, not the ceiling. `setBase(at:to:on:)` is the scripting path.
    ///
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func setValue(at index: Int32, to value: Float, on holder: ActorValueHolder) -> Bool

    /// Sets `index`'s base value outright, leaving every modifier intact —
    /// `SetActorValue`'s effect: "Sets the base value specified actor value on
    /// the actor to the passed-in value. Any modifiers are left intact."
    /// (<https://ck.uesp.net/wiki/SetActorValue_-_Actor>)
    ///
    /// Stored as the distance from the re-derived baseline rather than as the
    /// number itself, so a later level change or load-order change moves the
    /// value and this write still says exactly what it said.
    ///
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func setBase(at index: Int32, to value: Float, on holder: ActorValueHolder) -> Bool

    /// Raises `index`'s base by `delta`, which is what a skill advance and an
    /// attribute pick both do (items 20.5 and 20.6).
    ///
    /// The increment survives re-derivation and composes with it: a skill
    /// trained by five points is five points above whatever the records now
    /// author, so a level-up that raises the derived skill still lands on top
    /// of the training instead of replacing it.
    ///
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func incrementBase(
        at index: Int32,
        by delta: Float,
        on holder: ActorValueHolder
    ) -> Bool

    /// Raises one of the eighteen skills' base by `delta` — the entry point
    /// item 20.5's skill advancement writes through.
    ///
    /// A separate name rather than a comment on `incrementBase` because the
    /// guard is the point: a skill advance that lands on `Aggression` because a
    /// caller had an off-by-one index is a bug that should fail loudly at the
    /// one call site that only ever means a skill.
    ///
    /// - Returns: false for every index that is not one of the eighteen skills.
    @discardableResult
    func advanceSkill(
        at index: Int32,
        by delta: Float,
        on holder: ActorValueHolder
    ) -> Bool

    /// Adds `delta` to one of `index`'s modifier slots, which is how an effect
    /// applies and removes itself (issue 19.6) and how `ModActorValue` writes.
    ///
    /// Answers for a primary too since item 20.3, so a Fortify Health effect
    /// raises the bar's ceiling instead of being dropped.
    ///
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

    /// Forces `index`'s current value to `value` by moving its permanent
    /// modifier, which is what `ForceActorValue` documents:
    ///
    /// "this function modifies the 'permanent modifier' described in the Actor
    /// Value documentation, and that affects how the current value is computed.
    /// If an actor has a base health of 125 and you force their health to 0,
    /// then the permanent modifier will be set to -125, and their current
    /// health will become 0. If you then set the base health to 150, they will
    /// still have a permanent modifier of -125, so their current health will
    /// instantly become 25 (150 - 125)."
    /// (<https://ck.uesp.net/wiki/ForceActorValue_-_Actor>)
    ///
    /// The permanent modifier is therefore whatever makes the current value
    /// come out at `value` against everything that is not permanent — which is
    /// the wiki's own `-125` in an actor carrying nothing else.
    ///
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func forceValue(at index: Int32, to value: Float, on holder: ActorValueHolder) -> Bool

    /// The fraction of incoming damage `holder`'s resistance at `index`
    /// removes, capped.
    ///
    /// - Returns: nil when `index` is not a percentage resistance, which
    ///   includes `Damage Resist` and every non-resistance actor value. A
    ///   caller that gets nil has an effect whose resistance the armor formula
    ///   or no formula at all answers, and must not treat it as zero
    ///   resistance without saying so.
    func resistanceFraction(
        at index: Int32,
        on holder: ActorValueHolder,
        settings: ActorResistanceSettings
    ) -> Float?

    /// What one point of magic damage of `element`'s school is multiplied by
    /// before it reaches `holder`: Resist Magic first, then the element's own
    /// resistance, exactly as UESP states the order.
    ///
    /// - Parameter element: the MGEF's resistance actor value, or nil for an
    ///   effect that names none. A `nil` element still pays Resist Magic, which
    ///   is what makes a school-less magic effect resistible at all.
    /// - Returns: 1 when nothing resists, 0 when the actor is immune, and above
    ///   1 for a weakness — a negative resistance multiplies damage up, and two
    ///   weaknesses compound, which is what UESP's "Weakness to fire is
    ///   strengthened by weakness to magic" describes
    ///   (<https://en.uesp.net/wiki/Skyrim:Weakness_to_Fire>).
    func magicDamageMultiplier(
        element: Int32?,
        on holder: ActorValueHolder,
        settings: ActorResistanceSettings
    ) -> Float
}

extension ActorValueAccess {
    /// `resistanceFraction(at:on:settings:)` with the documented defaults.
    public func resistanceFraction(at index: Int32, on holder: ActorValueHolder) -> Float? {
        resistanceFraction(at: index, on: holder, settings: .documentedDefaults)
    }

    /// `magicDamageMultiplier(element:on:settings:)` with the documented defaults.
    public func magicDamageMultiplier(element: Int32?, on holder: ActorValueHolder) -> Float {
        magicDamageMultiplier(element: element, on: holder, settings: .documentedDefaults)
    }
}
