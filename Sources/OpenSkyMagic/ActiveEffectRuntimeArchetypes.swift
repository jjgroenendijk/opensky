// The archetype half of the active-effect runtime: target checks, the effects
// that act once (dispels, cures, absorb, world actions), the growing value of
// Accumulate Magnitude, and the influence the combat loop reads.
// See docs/engine/magic-archetypes.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

/// What kind of record put an effect on an actor, as the cures ask it.
nonisolated public enum ActiveEffectSourceCategory: Equatable, Sendable {
    /// A `SPEL` of type Disease.
    case disease
    /// An `ALCH` with the Poison flag.
    case poison
    case other
}

/// One thing the session must do for an effect that changes the world.
nonisolated public struct MagicWorldAction: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case began
        case ended
    }

    public let phase: Phase
    public let archetype: MagicWorldArchetype
    /// The MGEF, whose associated item names the hazard, weapon, or spell.
    public let effect: ReferenceKey
    public let target: ActorValueHolder
    public let magnitude: Float
    /// Who cast the effect, where one is known.
    public var caster: ReferenceKey?
    /// The stored effect's sequence on `target`; zero for an effect that acts once.
    public var sequence: UInt64 = 0
    /// The EFIT duration, seconds, of an effect that acts once.
    public var duration: Float = 0
    /// The EFIT area, feet, of an effect that acts once.
    public var area: UInt32 = 0

    public init(
        phase: Phase,
        archetype: MagicWorldArchetype,
        effect: ReferenceKey,
        target: ActorValueHolder,
        magnitude: Float
    ) {
        self.phase = phase
        self.archetype = archetype
        self.effect = effect
        self.target = target
        self.magnitude = magnitude
    }
}

extension ActiveEffectRuntime {
    /// Ward strength "charges up" over "a period of time of about one second"
    /// (<https://en.uesp.net/wiki/Skyrim:Ward>). UESP says "about", so this is an
    /// estimate.
    public static let accumulateSeconds: Float = 1

    /// The rule of the MGEF a stored effect applies.
    public func rule(of effect: ActiveEffect) -> MagicArchetypeRule? {
        effects.effect(key: effect.effect)?.effect.data
            .flatMap { MagicArchetypeRule.rule(for: $0.archetype) }
    }

    // MARK: - Influence

    /// The behaviour `holder`'s running effects force on it.
    public func influence(on holder: ActorValueHolder) -> ActorMagicInfluence {
        var influence = ActorMagicInfluence.none
        for effect in active(on: holder) {
            guard case let .influence(kind) = rule(of: effect) else { continue }
            switch kind {
            case .calm: influence.isCalmed = true
            case .frenzy: influence.isFrenzied = true
            case .demoralize, .turnUndead: influence.isFrightened = true
            case .rally: influence.isRallied = true
            case .paralysis: influence.isParalysed = true
            case .etherealize: influence.isEthereal = true
            }
        }
        return influence
    }

    /// Invisibility "is automatically dispelled when the invisibility is broken",
    /// such as by casting or attacking. Returns how many effects ended.
    @discardableResult
    public mutating func breakInvisibility(on holder: ActorValueHolder) -> Int {
        let flag = MagicArchetypeRule.heldFlag(
            actorValue: MagicArchetypeRule.invisibilityActorValue
        )
        let invisible = active(on: holder).filter { rule(of: $0) == flag }
        guard !invisible.isEmpty else { return 0 }
        let sequences = Set(invisible.map(\.sequence))
        return dispel(on: holder) { sequences.contains($0.sequence) }
    }

    /// Whether the MGEF's own conditions hold with `holder` as the subject. Detect Life
    /// asks this of each actor it may paint.
    public mutating func effectConditionsHold(
        _ effect: ReferenceKey, on holder: ActorValueHolder
    ) -> Bool {
        guard let resolved = effects.effect(key: effect) else { return false }
        return allows(resolved.effect.conditions, on: holder)
    }

    // MARK: - Target checks

    /// Why `application` cannot act on `target`, or nil when it can.
    func refusal(
        of application: MagicEffectApplication,
        on target: ActorValueHolder
    ) -> MagicEffectPlanFailure? {
        guard let rule = application.rule else { return nil }
        if rule == .influence(.turnUndead), !isUndead(target) {
            return .notUndead
        }
        if case let .world(archetype) = rule, let reason = worldRefusal(archetype, target) {
            return reason
        }
        if rule.capsTargetLevel {
            let level = Float(values.baseline(of: target).level)
            if level > application.magnitude {
                return .aboveLevelCap(application.archetype)
            }
        }
        return nil
    }

    // MARK: - Acting once

    /// Carries out everything an application does at the moment it lands.
    mutating func actOnce(
        _ application: MagicEffectApplication,
        caster: ReferenceKey?,
        on target: ActorValueHolder
    ) {
        switch application.rule {
        case nil, .actorValues, .valueAndParts:
            guard application.isInstant else { return }
            moveValues(application, on: target)
        case .absorb:
            guard application.isInstant else { return }
            for value in application.values {
                absorb(value.magnitude, at: value.index, application.isDetrimental, caster, target)
            }
        case let .dispel(filter):
            dispelMatching(filter, on: target)
        case let .world(archetype) where application.rule?.actsOnce == true:
            guard archetype != .stagger || !isStaggerImmune(target) else { return }
            var action = MagicWorldAction(
                phase: .began,
                archetype: archetype,
                effect: application.effect,
                target: target,
                magnitude: application.magnitude
            )
            action.caster = caster
            action.duration = application.duration
            action.area = application.area
            worldActions.append(action)
        case .world, .carrier, .influence, .heldFlag, .accumulate:
            break
        }
    }

    /// Stagger's duration "determines how long before the target can be staggered
    /// again", so a running stagger effect blocks a new one.
    private func isStaggerImmune(_ target: ActorValueHolder) -> Bool {
        active(on: target).contains { rule(of: $0) == .world(.stagger) }
    }

    /// Moves `application`'s values once: a detrimental effect damages them.
    private mutating func moveValues(
        _ application: MagicEffectApplication,
        on target: ActorValueHolder
    ) {
        for value in application.values where ActorValueIdentity.isVanilla(index: value.index) {
            if application.isDetrimental {
                values.damage(at: value.index, by: value.magnitude, on: target)
            } else {
                values.restore(at: value.index, by: value.magnitude, on: target)
            }
        }
    }

    /// Takes up to `amount` of `index` from one side and gives what was taken to
    /// the other. "If not 'detrimental', will instead drain the caster to replenish
    /// the target."
    mutating func absorb(
        _ amount: Float,
        at index: Int32,
        _ isDetrimental: Bool,
        _ caster: ReferenceKey?,
        _ target: ActorValueHolder
    ) {
        guard ActorValueIdentity.isVanilla(index: index), amount > 0 else { return }
        let casterHolder = caster.flatMap(holderResolver)
        let source = isDetrimental ? target : casterHolder
        let receiver = isDetrimental ? casterHolder : target
        guard let source else { return }
        let before = values.value(at: index, on: source) ?? 0
        values.damage(at: index, by: amount, on: source)
        let taken = max(0, before - (values.value(at: index, on: source) ?? before))
        guard let receiver, taken > 0 else { return }
        values.restore(at: index, by: taken, on: receiver)
    }

    /// Removes the effects `filter` names from `target`.
    private mutating func dispelMatching(_ filter: MagicDispelFilter, on target: ActorValueHolder) {
        let doomed = active(on: target).filter { effect in
            switch filter {
            case .timed: !effect.isConstant
            case .disease: sourceCategory(effect.source) == .disease
            case .poison: sourceCategory(effect.source) == .poison
            case .paralysis: rule(of: effect) == .influence(.paralysis)
            }
        }
        guard !doomed.isEmpty else { return }
        let sequences = Set(doomed.map(\.sequence))
        dispel(on: target) { sequences.contains($0.sequence) }
    }

    // MARK: - Stored effects

    /// Makes room for `application` before it is stored. "You may only have one
    /// cloak spell active at any given time, casting a second will cancel the
    /// first" (<https://en.uesp.net/wiki/Skyrim:Cloak>).
    mutating func clearRivals(of application: MagicEffectApplication, on target: ActorValueHolder) {
        guard application.rule == .world(.cloak) else { return }
        let rivals = active(on: target).filter { rule(of: $0) == .world(.cloak) }
        guard !rivals.isEmpty else { return }
        let sequences = Set(rivals.map(\.sequence))
        dispel(on: target) { sequences.contains($0.sequence) }
    }

    /// The world action a stored effect starts or ends, or nil for one that
    /// changes nothing outside its actor.
    func worldAction(
        _ phase: MagicWorldAction.Phase,
        of effect: ActiveEffect,
        on holder: ActorValueHolder
    ) -> MagicWorldAction? {
        guard let rule = rule(of: effect), case let .world(archetype) = rule, !rule.actsOnce
        else { return nil }
        var action = MagicWorldAction(
            phase: phase,
            archetype: archetype,
            effect: effect.effect,
            target: holder,
            magnitude: effect.peakMagnitude
        )
        action.caster = effect.caster
        action.sequence = effect.sequence
        return action
    }

    /// Grows each Accumulate Magnitude effect's held value toward its magnitude.
    func accumulate(_ effect: ActiveEffect, on holder: ActorValueHolder) -> ActiveEffect {
        guard rule(of: effect) == .accumulate, !effect.isConstant else { return effect }
        let share = min(1, effect.elapsed / Self.accumulateSeconds)
        var owned: [Int32: Float] = [:]
        for value in effect.values {
            let wanted = value.magnitude * share
            let change = wanted - value.applied
            guard change != 0 else { continue }
            guard values.addModifier(change, to: .temporary, at: value.index, on: holder)
            else { continue }
            owned[value.index] = wanted
        }
        return owned.isEmpty ? effect : effect.owningModifiers(owned)
    }
}
