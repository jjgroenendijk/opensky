// Active-effect accounting (issue #469, roadmap item 19.6): applying a magic
// item's effect list to an actor, holding the timed ones as a component, and
// ticking them on the same fixed step regeneration runs on.
//
// A thin layer beside `WorldStateStore`, following the `InventoryRuntime`,
// `QuestRuntime` and `ActorValueRuntime` precedent. The store is the generic
// substrate that knows about keys, components, journalling and snapshots and
// deliberately knows nothing about records; effects need `MagicEffectStore` to
// resolve an EFID and `ActorValueRuntime` to move a value, neither of which
// belongs inside it. Every mutation writes through `WorldStateStore.set`, so it
// lands in the journal, in the dirty counts and in the save.
//
// Headless and AppKit-free: this compiles into `openskycli` and is testable
// without a window. `@MainActor` only because the store it writes to is.
//
// Failure model: nothing here throws. An EFID that resolves to no MGEF, an
// archetype with no implementation, a condition list that evaluates false —
// each is a tally bucket and an entry that applied nothing, never an error. A
// potion with one unimplemented effect still applies its other ones.
//
// Mutating rather than pure because the tally advances as it works, the same
// reason `ConditionEvaluator` is mutating.
//
// Documented in docs/engine/magic.md.

import Foundation

@MainActor
struct ActiveEffectRuntime {
    /// Simulation step effects advance in, matching `ActorValueRuntime` so a
    /// frame drives both the same way. 1/60 s.
    static let fixedStepSeconds = ActorValueRuntime.fixedStepSeconds

    /// Most whole steps one `advance(delta:)` runs, so a multi-second stall
    /// cannot spend minutes ticking effects in a single frame.
    static let maximumStepsPerAdvance = ActorValueRuntime.maximumStepsPerAdvance

    /// The actor-value surface every application ultimately writes through.
    let values: ActorValueRuntime
    /// Load-order MGEF lookup behind every EFID.
    let effects: MagicEffectStore
    /// What an effect entry's CTDA list is evaluated against.
    ///
    /// A whole context rather than a yes/no closure, so the same evaluator the
    /// rest of the engine uses answers here and an unevaluatable condition is
    /// the documented reason-tagged false rather than a silent pass.
    var conditions: ConditionContext
    let conditionRegistry: ConditionFunctionRegistry
    /// What the runtime did and declined to do. Not `private(set)`: the tick
    /// half lives in `ActiveEffectRuntimeTick.swift` and a file-private setter
    /// would put it out of reach there.
    var tally = ActiveEffectTally()

    init(
        values: ActorValueRuntime,
        effects: MagicEffectStore,
        conditions: ConditionContext = ConditionContext(),
        conditionRegistry: ConditionFunctionRegistry = .standard
    ) {
        self.values = values
        self.effects = effects
        self.conditions = conditions
        self.conditionRegistry = conditionRegistry
    }

    var store: WorldStateStore {
        values.store
    }

    // MARK: - Reading

    /// Every effect currently acting on `holder`.
    func state(of holder: ActorValueHolder) -> ActiveEffectState {
        store.component(ActiveEffectState.self, for: holder.key) ?? ActiveEffectState()
    }

    /// `holder`'s effects in application order.
    func active(on holder: ActorValueHolder) -> [ActiveEffect] {
        state(of: holder).effects
    }

    /// Whether `holder` carries an application of `effect` — the shape
    /// `HasMagicEffect` needs (issue 19.11 registers the function itself).
    func hasMagicEffect(_ effect: ReferenceKey, on holder: ActorValueHolder) -> Bool {
        state(of: holder).hasEffect(effect)
    }

    // MARK: - Applying

    /// Applies one magic item's effect list to `target`.
    ///
    /// Every entry is planned and applied independently: an entry the engine
    /// cannot carry out is counted and skipped, and the rest still land. Instant
    /// entries move the actor value immediately and are stored nowhere; timed
    /// ones become components.
    ///
    /// - Parameter isConstant: whether the record handing over the list is a
    ///   constant effect — a worn item's enchantment (issue #472). Every entry
    ///   then becomes a `constant` effect that persists until it is dispelled,
    ///   rather than an instant application of its zero duration.
    /// - Returns: the timed effects that were stored, in application order.
    @discardableResult
    mutating func apply(
        _ entries: [MagicItemEffect],
        fromPlugin pluginName: String,
        source: ActiveEffectSource,
        caster: ReferenceKey? = nil,
        isConstant: Bool = false,
        on target: ActorValueHolder
    ) -> [ActiveEffect] {
        var stored: [ActiveEffect] = []
        for entry in entries {
            guard let resolved = effects.resolve(entry, fromPlugin: pluginName) else {
                tally.noteUnresolvedEffect()
                continue
            }
            guard allows(entry.conditions, on: target) else {
                tally.noteConditionSkipped()
                continue
            }
            let outcome = MagicEffectPlanner.plan(
                effect: resolved,
                entry: entry,
                isConstant: isConstant,
                resolveKeyword: { link in
                    effects.resolvedID(link, fromPlugin: resolved.sourcePlugin)
                        .map(ReferenceKey.init(resolved:))
                }
            )
            switch outcome {
            case let .skip(reason):
                tally.note(reason)
            case let .apply(application) where application.isInstant:
                applyInstant(application, on: target)
            case let .apply(application):
                let effect = storeTimed(
                    application,
                    source: source,
                    caster: caster,
                    on: target
                )
                if let effect {
                    stored.append(effect)
                }
            }
        }
        return stored
    }

    // MARK: - Dispelling

    /// Removes every effect on `holder` that `predicate` selects, handing back
    /// whatever modifier slot each of them owned.
    ///
    /// - Returns: how many effects were removed.
    @discardableResult
    mutating func dispel(
        on holder: ActorValueHolder,
        where predicate: (ActiveEffect) -> Bool
    ) -> Int {
        let state = state(of: holder)
        let doomed = state.effects.filter(predicate)
        guard !doomed.isEmpty else { return 0 }
        release(doomed, on: holder)
        write(state.removing(sequences: Set(doomed.map(\.sequence))), for: holder)
        tally.noteDispelled(doomed.count)
        return doomed.count
    }

    /// Removes every effect on `holder` — the Dispel archetype's shape, and
    /// what a dev control offers.
    @discardableResult
    mutating func dispelAll(on holder: ActorValueHolder) -> Int {
        dispel(on: holder) { _ in true }
    }

    // MARK: - Reload

    /// Re-establishes the temporary modifier slot every stored effect owns.
    ///
    /// The save deliberately does not persist the temporary modifier (see
    /// `OpenSkySaveFormat.ChunkTag.actorValueOverrides`), because the effect that
    /// established it is what re-establishes it. This is that step, and a loaded
    /// session calls it once per actor carrying effects.
    ///
    /// - Returns: how many actor values were re-established.
    @discardableResult
    func reestablishModifiers(on holder: ActorValueHolder) -> Int {
        let owned = state(of: holder).ownedModifiers
        for (index, amount) in owned.sorted(by: { $0.key < $1.key }) {
            values.setModifier(amount, for: .temporary, at: index, on: holder)
        }
        return owned.count
    }

    // MARK: - Private

    /// Whether an effect entry's conditions hold for `target`.
    ///
    /// An empty list is true, which is what an unconditioned entry means; a
    /// list this engine cannot evaluate is false and is counted, never a silent
    /// pass. Both run-ons name the target: an effect entry's conditions are
    /// asked about the actor receiving the effect.
    private mutating func allows(
        _ list: ConditionList,
        on target: ActorValueHolder
    ) -> Bool {
        guard !list.conditions.isEmpty else { return true }
        var context = conditions
        context.subject = target.key
        context.target = target.key
        var evaluator = ConditionEvaluator(context: context, registry: conditionRegistry)
        let outcome = evaluator.evaluate(list)
        conditions.random = evaluator.context.random
        return outcome.isTrue
    }

    /// Applies a zero-duration effect once and stores nothing.
    private mutating func applyInstant(
        _ application: MagicEffectApplication,
        on target: ActorValueHolder
    ) {
        for value in application.values {
            if application.isDetrimental {
                values.damage(at: value.index, by: value.magnitude, on: target)
            } else {
                values.restore(at: value.index, by: value.magnitude, on: target)
            }
        }
        tally.noteInstant()
    }

    /// Stores a timed effect, applying the stacking rules first.
    ///
    /// - Returns: the stored effect, or nil when a stacking rule refused it.
    private mutating func storeTimed(
        _ application: MagicEffectApplication,
        source: ActiveEffectSource,
        caster: ReferenceKey?,
        on target: ActorValueHolder
    ) -> ActiveEffect? {
        var state = state(of: target)
        if application.refusesRecast, state.hasEffect(application.effect) {
            tally.noteRecastRefused()
            return nil
        }
        if let keyword = application.stackKeyword {
            let rivals = state.effects.filter { $0.stackKeyword == keyword }
            let strongest = rivals.map(\.peakMagnitude).max() ?? -.greatestFiniteMagnitude
            let incoming = application.values.map(\.magnitude).max() ?? 0
            guard incoming > strongest else {
                tally.notePeakStackResolved()
                return nil
            }
            if !rivals.isEmpty {
                release(rivals, on: target)
                state = state.removing(sequences: Set(rivals.map(\.sequence)))
                tally.notePeakStackResolved()
            }
        }
        var effect = ActiveEffect(
            sequence: state.nextSequence,
            source: source,
            effect: application.effect,
            caster: caster,
            mode: application.mode,
            isDetrimental: application.isDetrimental,
            duration: application.duration,
            values: application.values,
            stackKeyword: application.stackKeyword
        )
        if application.mode.ownsModifierSlot {
            effect = effect.owningModifiers(claim(effect, on: target))
        }
        write(state.adding(effect), for: target)
        tally.noteApplied()
        return effect
    }

    /// Adds each of `effect`'s values to the temporary modifier slot, reporting
    /// what it now owns.
    private func claim(_ effect: ActiveEffect, on target: ActorValueHolder) -> [Int32: Float] {
        var owned: [Int32: Float] = [:]
        for value in effect.values {
            let delta = effect.delta(of: value)
            guard values.addModifier(delta, to: .temporary, at: value.index, on: target) else {
                continue
            }
            owned[value.index] = delta
        }
        return owned
    }

    /// Hands back every modifier slot `doomed` owns, so an expired or dispelled
    /// effect leaves the value exactly where it found it. Internal because the
    /// tick half calls it on expiry.
    func release(_ doomed: [ActiveEffect], on holder: ActorValueHolder) {
        for effect in doomed {
            for value in effect.values where value.applied != 0 {
                values.addModifier(-value.applied, to: .temporary, at: value.index, on: holder)
            }
        }
    }

    /// Stores `state`, dropping the whole component once it is empty so an
    /// actor whose effects all expired stops being dirty for this slot.
    /// Internal for the reason `release` is.
    func write(_ state: ActiveEffectState, for holder: ActorValueHolder) {
        if state.isEmpty {
            store.reset(.activeEffects, for: holder.key)
        } else {
            store.set(state, for: holder.key, in: holder.cell)
        }
    }
}
