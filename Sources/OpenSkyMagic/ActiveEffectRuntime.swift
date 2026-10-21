// Active-effect accounting: applies a magic item's effects, stores the timed ones, and
// ticks them on the regeneration step, writing through `WorldStateStore.set`. Nothing
// throws: an unresolved EFID, an unimplemented archetype or a false condition is a tally
// entry, and the other effects still apply. See docs/engine/magic.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyWorldState

@MainActor
public struct ActiveEffectRuntime {
    /// Simulation step effects advance in, matching `ActorValueRuntime` so a
    /// frame drives both the same way. 1/60 s.
    public static let fixedStepSeconds = ActorValueStep.fixedStepSeconds

    /// Most whole steps one `advance(delta:)` runs, so a multi-second stall
    /// cannot spend minutes ticking effects in a single frame.
    public static let maximumStepsPerAdvance = ActorValueStep.maximumStepsPerAdvance

    /// The actor-value surface every application ultimately writes through.
    public let values: any ActorValueAccess
    /// Load-order MGEF lookup behind every EFID.
    public let effects: MagicEffectStore
    /// What an effect entry's CTDA list is evaluated against.
    ///
    /// A whole context rather than a yes/no closure, so the same evaluator the
    /// rest of the engine uses answers here and an unevaluatable condition is
    /// the documented reason-tagged false rather than a silent pass.
    public var conditions: ConditionContext
    public let conditionRegistry: ConditionFunctionRegistry
    /// What the runtime did and declined to do. Not `private(set)`: the tick
    /// half lives in `ActiveEffectRuntimeTick.swift` and a file-private setter
    /// would put it out of reach there.
    public var tally = ActiveEffectTally()
    /// The tick walks holders in key order; this keeps that order between frames.
    /// Internal, because the tick half reads it from another file.
    var holderOrder = ReferenceKeyOrder()
    /// World changes the effects asked for, oldest first. The coordinator drains
    /// them after each change.
    public var worldActions: [MagicWorldAction] = []
    /// The actor-value holder of a caster, for Absorb. Only the player without a world.
    public var holderResolver: (ReferenceKey) -> ActorValueHolder? = { key in
        key == .player ? .player : nil
    }

    /// What kind of record a source is, for the cures.
    public var sourceCategory: (ActiveEffectSource) -> ActiveEffectSourceCategory = { _ in .other }
    /// Whether an actor carries `ActorTypeUndead`, for Turn Undead.
    public var isUndead: (ActorValueHolder) -> Bool = { _ in false }
    /// The spell-side `CTDA` list of the entry a stored effect came from, which is
    /// checked again every second. Nil when the source is not known here.
    public var entryConditions: (ActiveEffect) -> ConditionList? = { _ in nil }
    /// Seconds toward the next condition check. Internal for the tick file.
    var conditionClock: Float = 0
    /// What the effects being applied right now came from, for `EffectWasDualCast`
    /// and the absorb step. The caller sets it around one `apply`.
    public var application = MagicApplicationContext()

    public init(
        values: any ActorValueAccess,
        effects: MagicEffectStore,
        conditions: ConditionContext = ConditionContext(),
        conditionRegistry: ConditionFunctionRegistry
    ) {
        self.values = values
        self.effects = effects
        self.conditions = conditions
        self.conditionRegistry = conditionRegistry
    }

    public var store: WorldStateStore {
        values.store
    }

    // MARK: - Reading

    /// Every effect currently acting on `holder`.
    public func state(of holder: ActorValueHolder) -> ActiveEffectState {
        store.component(ActiveEffectState.self, for: holder.key) ?? ActiveEffectState()
    }

    /// `holder`'s effects in application order.
    public func active(on holder: ActorValueHolder) -> [ActiveEffect] {
        state(of: holder).effects
    }

    /// Whether `holder` carries an application of `effect`, as `HasMagicEffect` needs.
    public func hasMagicEffect(_ effect: ReferenceKey, on holder: ActorValueHolder) -> Bool {
        state(of: holder).hasEffect(effect)
    }

    // MARK: - Applying

    /// Applies one magic item's effects to `target`, each on its own: instant ones move
    /// the value now, timed ones are stored. `isConstant` (a worn enchantment) makes each a
    /// `constant` effect. Returns the stored timed effects, in order.
    @discardableResult
    public mutating func apply(
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
            // "Effect-side conditions are checked when an effect is applied and
            // determine whether an actor will ever receive the effect, while
            // spell-side conditions determine when the effect is active."
            // (<https://ck.uesp.net/wiki/Magic_Effect>)
            guard allows(resolved.effect.conditions, on: target) else {
                tally.noteEffectConditionSkipped()
                continue
            }
            let entryHolds = allows(entry.conditions, on: target)
            guard entryHolds || isConstant else {
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
            case let .apply(application):
                if let reason = refusal(of: application, on: target) {
                    tally.note(reason)
                    continue
                }
                if entryHolds {
                    actOnce(application, caster: caster, on: target)
                }
                if application.isInstant {
                    tally.noteInstant()
                } else if
                    let effect = storeTimed(
                        application,
                        source: source,
                        caster: caster,
                        on: target,
                        suspended: !entryHolds
                    )
                {
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
    public mutating func dispel(
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
    public mutating func dispelAll(on holder: ActorValueHolder) -> Int {
        dispel(on: holder) { _ in true }
    }

    // MARK: - Reload

    /// Rebuilds each stored effect's temporary modifier after a load, because the save
    /// skips that slot (`ChunkTag.actorValueOverrides`). Returns the values rebuilt.
    @discardableResult
    public func reestablishModifiers(on holder: ActorValueHolder) -> Int {
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
    mutating func allows(
        _ list: ConditionList,
        on target: ActorValueHolder
    ) -> Bool {
        guard !list.conditions.isEmpty else { return true }
        var context = conditions
        context.subject = target.key
        context.target = target.key
        context.magicApplication = application
        var evaluator = ConditionEvaluator(context: context, registry: conditionRegistry)
        let outcome = evaluator.evaluate(list)
        conditions.random = evaluator.context.random
        return outcome.isTrue
    }

    /// Stores a timed effect, applying the stacking rules first.
    ///
    /// - Returns: the stored effect, or nil when a stacking rule refused it.
    private mutating func storeTimed(
        _ application: MagicEffectApplication,
        source: ActiveEffectSource,
        caster: ReferenceKey?,
        on target: ActorValueHolder,
        suspended: Bool = false
    ) -> ActiveEffect? {
        if application.refusesRecast, state(of: target).hasEffect(application.effect) {
            tally.noteRecastRefused()
            return nil
        }
        clearRivals(of: application, on: target)
        var state = state(of: target)
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
        effect.wasDualCast = self.application.isDualCast
        if suspended {
            effect = effect.suspended(true)
        } else if application.mode.ownsModifierSlot, !grows(application) {
            effect = effect.owningModifiers(claim(effect, on: target))
        }
        write(state.adding(effect), for: target)
        if !suspended, let action = worldAction(.began, of: effect, on: target) {
            worldActions.append(action)
        }
        tally.noteApplied()
        return effect
    }

    /// Whether the held value starts at zero and grows on each tick.
    func grows(_ application: MagicEffectApplication) -> Bool {
        application.rule == .accumulate && application.mode != .constant
    }

    /// Adds each of `effect`'s values to the temporary modifier slot, reporting
    /// what it now owns.
    func claim(_ effect: ActiveEffect, on target: ActorValueHolder) -> [Int32: Float] {
        var owned: [Int32: Float] = [:]
        for value in effect.values where ActorValueIdentity.isVanilla(index: value.index) {
            let delta = effect.delta(of: value)
            guard values.addModifier(delta, to: .temporary, at: value.index, on: target) else {
                continue
            }
            owned[value.index] = delta
        }
        return owned
    }

    /// Returns every slot `doomed` holds, so the value goes back where it was. A
    /// primary's current value drops with its maximum but stays at least 1
    /// (<https://en.uesp.net/wiki/Skyrim:Fortify_Health>), so expiry never kills.
    public mutating func release(_ doomed: [ActiveEffect], on holder: ActorValueHolder) {
        for effect in doomed {
            if let action = worldAction(.ended, of: effect, on: holder) {
                worldActions.append(action)
            }
            for value in effect.values where value.applied != 0 {
                let kind = ActorValueIdentity.kind(at: value.index)
                let before = kind.map { values.current(of: holder)[$0] }
                values.addModifier(-value.applied, to: .temporary, at: value.index, on: holder)
                if
                    let kind, let before, before > 0,
                    values.current(of: holder)[kind] < Self.expiryFloor
                {
                    values.set(kind, to: Self.expiryFloor, on: holder)
                }
            }
        }
    }

    /// What a primary is left with when an expiring modifier would otherwise
    /// empty it: "at least 1 health point" (UESP, Fortify Health).
    public static let expiryFloor: Float = 1

    /// Stores `state`, dropping the whole component once it is empty so an
    /// actor whose effects all expired stops being dirty for this slot.
    /// Internal for the reason `release` is.
    public func write(_ state: ActiveEffectState, for holder: ActorValueHolder) {
        if state.isEmpty {
            store.reset(.activeEffects, for: holder.key)
        } else {
            store.set(state, for: holder.key, in: holder.cell)
        }
    }
}
