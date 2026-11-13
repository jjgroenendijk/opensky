// The magic frame step: effects, casting and the commands they leave for the app.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import OpenSkyWorldState

extension MagicCoordinator.FrameStep {
    /// A hand pressed while the player shouts does not begin its cast, and a new press
    /// says why. A cast already running is left to finish.
    func refusingCastsDuringShout(_ intent: CastingIntent) -> CastingIntent {
        var refused = intent
        let shouting = !coordinator.shoutMachine.isIdle
        for hand in SpellHand.allCases {
            let pressed = intent.isHeld(hand)
            defer {
                if pressed {
                    coordinator.castingState.castPressed.insert(hand)
                } else {
                    coordinator.castingState.castPressed.remove(hand)
                }
            }
            guard
                shouting, pressed, coordinator.itemUse.hasReadiedSpell(in: hand),
                !(coordinator.caster?.phase(of: hand).isCasting ?? false)
            else { continue }
            if !coordinator.castingState.castPressed.contains(hand) {
                coordinator.pendingCommands
                    .append(.notice(coordinator.texts.castNotices[.castWhileShouting]))
            }
            switch hand {
            case .left: refused.leftHeld = false
            case .right: refused.rightHeld = false
            }
        }
        return refused
    }
}

extension MagicCoordinator.FrameStep {
    /// Whole effect steps for the delta this frame simulated, over the player
    /// and the resident actors. A menu-paused frame delivers delta 0.
    public func advanceEffects(delta: Float) -> [MagicCommand] {
        guard var runtime = coordinator.effects else { return takeCommands() }
        let holders = coordinator.world.regeneratingHolders()
        let scales = coordinator.slowTimeClock.timeScales
        if scales.isSlowed {
            // The player's effects run on the player's clock, so Slow Time ends on time.
            let split = Dictionary(grouping: holders) { $0.key == .player }
            runtime.advance(
                delta: delta,
                accumulator: &coordinator.accumulator,
                over: split[false] ?? []
            )
            runtime.advance(
                delta: delta * scales.player / scales.world,
                accumulator: &coordinator.playerAccumulator,
                over: split[true] ?? []
            )
        } else {
            runtime.advance(delta: delta, accumulator: &coordinator.accumulator, over: holders)
            coordinator.playerAccumulator = coordinator.accumulator
        }
        coordinator.effects = runtime
        coordinator.archetypeActions.performWorldActions()
        coordinator.abilityReconciler.maintainCarriedEffects(delta: delta)
        coordinator.cloakPulses.pulseCloaks(delta: delta)
        coordinator.holdEffects.advanceHolds(delta: delta)
        coordinator.worldArchetypeActions.advanceLights(delta: delta)
        return takeCommands()
    }

    /// Runs the effects through `seconds` of real time a rest skipped. The commands
    /// they raise leave with the next frame.
    public func elapseRestTime(seconds: Double) {
        guard var runtime = coordinator.effects else { return }
        runtime.elapse(seconds: seconds, over: coordinator.world.regeneratingHolders())
        coordinator.effects = runtime
        coordinator.archetypeActions.performWorldActions()
    }

    /// Returns and empties what the effects asked of the app. A command raised
    /// outside a frame step, such as by a script, also leaves with the next one.
    public func takeCommands() -> [MagicCommand] {
        defer { coordinator.pendingCommands = [] }
        return coordinator.pendingCommands
    }

    /// One frame of casting. A frame in a menu or in free-fly charges nothing
    /// for the player, but NPC casts still advance. `events` are the player graph's.
    public func advanceCasting(
        _ intent: CastingIntent,
        isPlayerControlled: Bool,
        events: [String] = [],
        weaponsDrawn: Bool? = nil
    ) -> [MagicCommand] {
        guard let caster = coordinator.caster else { return takeCommands() }
        let playerIntent = isPlayerControlled
            ? refusingCastsDuringShout(coordinator.castingCues.latched(intent, events: events)) :
            .still
        caster.acceptFrame(playerIntent, on: .player)
        for failure in caster.takePlayerFailures() {
            let text = coordinator.texts.castNotices[CastNoticeText.notice(for: failure) ?? .ok]
            if !text.isEmpty {
                coordinator.pendingCommands.append(.notice(text))
            }
        }
        advanceActorCasts(delta: intent.deltaTime)
        coordinator.runePlacement.advanceRunes(delta: intent.deltaTime)
        coordinator.summonCommands.advanceCommanded(delta: intent.deltaTime)
        coordinator.castingCues.advanceCastingCues(weaponsDrawn: weaponsDrawn)
        return takeCommands()
    }

    /// Every NPC cast in flight, charged on the player's clock.
    func advanceActorCasts(delta: Float) {
        guard let caster = coordinator.caster, delta > 0 else { return }
        for key in caster.castingActors where key != .player {
            guard let holder = coordinator.world.actorValueHolder(for: key) else { continue }
            caster.advance(delta: delta, on: holder)
        }
    }

    /// Takes the world actions the runtime queued, leaving none.
    func takeWorldActions() -> [MagicWorldAction] {
        guard var runtime = coordinator.effects, !runtime.worldActions.isEmpty else { return [] }
        let actions = runtime.worldActions
        runtime.worldActions = []
        coordinator.effects = runtime
        return actions
    }

    /// Takes the actors a calm from around its caster reached, leaving none.
    func takeHealing() -> [MagicHealingUse] {
        guard var runtime = coordinator.effects, !runtime.healing.isEmpty else { return [] }
        let healing = runtime.healing
        runtime.healing = []
        coordinator.effects = runtime
        return healing
    }

    func takeCalmedAround() -> [ReferenceKey] {
        guard var runtime = coordinator.effects, !runtime.calmedAround.isEmpty else { return [] }
        let calmed = runtime.calmedAround
        runtime.calmedAround = []
        coordinator.effects = runtime
        return calmed
    }
}
