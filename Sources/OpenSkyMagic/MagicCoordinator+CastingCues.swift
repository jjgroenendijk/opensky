// The casting hands' sounds and art: each frame compares every hand with the last and
// asks the app to start or stop what the spell's costliest effect names. The rules live
// in `CastingCueRule` and `SpellReleaseLatch`. See docs/engine/spellcasting.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

extension MagicCoordinator {
    /// The hold each of the player's hands gets: a released hand waits for its event.
    func latched(_ intent: CastingIntent, events: [String]) -> CastingIntent {
        guard let caster else { return intent }
        var latched = intent
        for hand in SpellHand.allCases {
            let event = SpellFireGraphNames.event(of: hand)
            let held = releaseLatch.hold(
                hand,
                pressed: intent.isHeld(hand),
                phase: caster.phase(of: hand),
                fired: events.contains { $0.caseInsensitiveCompare(event) == .orderedSame },
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
    public func wantsCast(_ hand: SpellHand) -> Bool {
        (caster?.phase(of: hand).isCasting ?? false) && !releaseLatch.isWaiting(hand)
    }

    func advanceCastingCues(weaponsDrawn: Bool?) {
        guard let caster else { return }
        let completed = caster.takeCompletedCasts()
        var slots = Set(castingViews.keys)
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
                from: castingViews[slot] ?? CastingHandView(),
                to: new,
                cast: completed.last { $0.slot == slot }?.spell
            )
            emit(cues, by: slot.caster)
            castingViews[slot] = new.phase == .idle ? nil : new
        }
        let readied = world.actorValueHolder(for: .player).map { holder in
            SpellHand.allCases.compactMap { caster.spellbook.state(of: holder).spell(in: $0) }
        } ?? []
        emit(
            CastingCueRule.drawCues(drawn: wasWeaponsDrawn, now: weaponsDrawn, readied: readied),
            by: .player
        )
        wasWeaponsDrawn = weaponsDrawn
    }

    /// The panel line: how many cues went out, the last one, and a waiting release.
    var castingCueText: String {
        let last = lastCastingCue.map { "; last: \($0)" } ?? ""
        let waiting = SpellHand.allCases.filter(releaseLatch.isWaiting)
            .map { "; release waits for \(SpellFireGraphNames.event(of: $0))" }
            .joined()
        return "Casting cues: \(castingCueCount)\(last)\(waiting)"
    }

    private func view(of state: SpellCastState) -> CastingHandView {
        CastingHandView(
            phase: state.phase,
            spell: state.spell,
            isDualCast: state.isDualCast,
            isConcentration: state.spell
                .flatMap { caster?.spellbook.record($0)?.data?.castingType } == .concentration
        )
    }

    private func emit(_ cues: [CastingCue], by key: ReferenceKey) {
        for cue in cues {
            guard
                let spell = caster?.spellbook.record(cue.spell),
                let effect = spell.effects.max(by: { $0.cost < $1.cost })?.effect,
                let command = command(for: cue, effect: effect, caster: key)
            else { continue }
            pendingCommands.append(command)
            castingCueCount += 1
            if cue.starts {
                lastCastingCue = "\(Self.name(of: cue.what)) of \(spell.displayName)"
            }
        }
    }

    private func command(
        for cue: CastingCue, effect: ResolvedMagicEffect, caster key: ReferenceKey
    ) -> MagicCommand? {
        switch cue.what {
        case let .sound(kind):
            guard
                let store = effects?.effects,
                let descriptor = effect.effect.sounds.first(where: { $0.kind == kind.rawValue })?
                    .descriptor,
                let id = store.resolvedID(descriptor, fromPlugin: effect.sourcePlugin),
                let formID = store.loadOrderFormID(id)
            else { return nil }
            return .castingSound(formID, caster: key, starts: cue.starts)
        case let .art(dual):
            let data = effect.effect.data
            guard let art = (dual ? data?.dualCastArt : nil) ?? data?.castingArt else { return nil }
            return .castingArt(
                art, plugin: effect.sourcePlugin, caster: key, starts: cue.starts
            )
        }
    }

    private static func name(of what: CastingCue.What) -> String {
        switch what {
        case let .sound(kind): "\(kind.name) sound"
        case .art(dual: true): "dual casting art"
        case .art(dual: false): "casting art"
        }
    }
}
