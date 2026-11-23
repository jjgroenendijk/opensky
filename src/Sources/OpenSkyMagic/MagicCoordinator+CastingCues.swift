// The casting hands' sounds and art: each frame compares every hand with the last and
// asks the app to start or stop what the spell's costliest effect names. The rules live
// in `CastingCueRule` and `SpellReleaseLatch`. See docs/engine/spellcasting.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

extension MagicCoordinator.CastingCueTracker {
    /// The hold each of the player's hands gets: a released hand waits for its event.
    func latched(_ intent: CastingIntent, events: [String]) -> CastingIntent {
        guard let caster = coordinator.caster else { return intent }
        var latched = intent
        for hand in SpellHand.allCases {
            let names = coordinator.heldStaves.heldStaff(of: .player, in: hand) == nil
                ? [SpellFireGraphNames.event(of: hand)]
                : [SpellFireGraphNames.event(of: hand), SpellFireGraphNames.staff]
            let held = coordinator.castingState.releaseLatch.hold(
                hand,
                state: (intent.isHeld(hand), caster.phase(of: hand)),
                fired: events.contains { event in
                    names.contains { $0.caseInsensitiveCompare(event) == .orderedSame }
                },
                delta: intent.deltaTime
            )
            switch hand {
            case .left: latched.leftHeld = held
            case .right: latched.rightHeld = held
            }
        }
        return latched
    }

    /// What the player's graph hears as `bWantCastLeft` or `bWantCastRight`: a hand
    /// whose release waits no longer wants to cast, so the graph throws the spell.
    func wantsCast(_ hand: SpellHand) -> Bool {
        (coordinator.caster?.phase(of: hand).isCasting ?? false) && !coordinator.castingState
            .releaseLatch
            .isWaiting(hand)
    }

    func advanceCastingCues(weaponsDrawn: Bool?) {
        guard let caster = coordinator.caster else { return }
        let completed = caster.takeCompletedCasts()
        var slots = Set(coordinator.castingState.castingViews.keys)
            .union(coordinator.castingState.handArt.keys)
        for key in caster.castingActors + [.player] {
            for hand in SpellHand.allCases {
                slots.insert(CastSlot(caster: key, hand: hand))
            }
        }
        let ordered = slots.sorted {
            ($0.caster, $0.hand.rawValue) < ($1.caster, $1.hand.rawValue)
        }
        for slot in ordered {
            let new = view(of: caster.state(of: slot.hand, on: slot.caster))
            let cues = CastingCueRule.cues(
                from: coordinator.castingState.castingViews[slot] ?? CastingHandView(),
                to: new,
                cast: completed.last { $0.slot == slot }?.spell
            )
            emit(cues, by: slot.caster)
            coordinator.castingState.castingViews[slot] = new.phase == .idle ? nil : new
            let wanted = slot.caster == .player
                ? (weaponsDrawn == true ? readiedSpell(in: slot.hand) : nil)
                : (new.phase.isCasting ? new.spell : nil)
            emit(
                CastingCueRule.artCues(
                    slot.hand, shown: coordinator.castingState.handArt[slot], wanted: wanted
                ),
                by: slot.caster
            )
            coordinator.castingState.handArt[slot] = wanted
        }
        let readied = SpellHand.allCases.compactMap(readiedSpell(in:))
        emit(
            CastingCueRule.drawCues(
                drawn: coordinator.castingState.wasWeaponsDrawn,
                now: weaponsDrawn,
                readied: readied
            ),
            by: .player
        )
        if coordinator.castingState.wasWeaponsDrawn == true, weaponsDrawn == false {
            coordinator.weaponArchetypes.dismissBoundWeaponsOnSheathe(of: .player)
        }
        coordinator.castingState.wasWeaponsDrawn = weaponsDrawn
    }

    /// The spell the player holds ready in `hand`.
    private func readiedSpell(in hand: SpellHand) -> ReferenceKey? {
        guard
            let caster = coordinator.caster,
            let holder = coordinator.world.actorValueHolder(for: .player)
        else { return nil }
        return caster.spellbook.state(of: holder).spell(in: hand)
    }

    /// The readout line: how many cues went out, the last one, and a waiting release.
    var castingCueText: String {
        let last = coordinator.castingState.lastCastingCue.map { "; last: \($0)" } ?? ""
        let waiting = SpellHand.allCases.filter(coordinator.castingState.releaseLatch.isWaiting)
            .map { "; release waits for \(SpellFireGraphNames.event(of: $0))" }
            .joined()
        return "Casting cues: \(coordinator.castingState.castingCueCount)\(last)\(waiting)"
    }

    private func view(of state: SpellCastState) -> CastingHandView {
        CastingHandView(
            phase: state.phase,
            spell: state.spell,
            isDualCast: state.isDualCast,
            isConcentration: state.spell
                .flatMap { coordinator.caster?.spellbook.record($0)?.data?.castingType } ==
                .concentration
        )
    }

    private func emit(_ cues: [CastingCue], by key: ReferenceKey) {
        for cue in cues {
            guard
                let spell = coordinator.caster?.spellbook.record(cue.spell),
                let effect = Self.mainEffect(of: spell)
            else { continue }
            if case let .art(hand) = cue.what, let light = effect.effect.data?.castingLight {
                coordinator.pendingCommands.append(.castingLight(
                    light, plugin: effect.sourcePlugin, caster: key, hand: hand,
                    starts: cue.starts
                ))
            }
            guard let command = command(for: cue, effect: effect, caster: key) else { continue }
            coordinator.pendingCommands.append(command)
            coordinator.castingState.castingCueCount += 1
            if cue.starts {
                coordinator.castingState.lastCastingCue =
                    "\(Self.name(of: cue.what)) of \(spell.displayName)"
            }
        }
    }

    private func command(
        for cue: CastingCue, effect: ResolvedMagicEffect, caster key: ReferenceKey
    ) -> MagicCommand? {
        switch cue.what {
        case let .sound(kind):
            guard
                let store = coordinator.effects?.effects,
                let descriptor = effect.effect.sounds.first(where: { $0.kind == kind.rawValue })?
                    .descriptor,
                let id = store.resolvedID(descriptor, fromPlugin: effect.sourcePlugin),
                let formID = store.loadOrderFormID(id)
            else { return nil }
            return .castingSound(formID, caster: key, starts: cue.starts)
        case let .art(hand):
            guard let art = effect.effect.data?.castingArt else { return nil }
            return .castingArt(
                art, plugin: effect.sourcePlugin, caster: key, hand: hand, starts: cue.starts
            )
        }
    }

    static func mainEffect(of spell: ResolvedSpell) -> ResolvedMagicEffect? {
        MainMagicEffect.index(
            of: spell.effects, concentration: spell.data?.castingType == .concentration
        ).flatMap { spell.effects[$0].effect }
    }

    private static func name(of what: CastingCue.What) -> String {
        switch what {
        case let .sound(kind): "\(kind.name) sound"
        case .art(.left): "left hand art"
        case .art(.right): "right hand art"
        }
    }
}
