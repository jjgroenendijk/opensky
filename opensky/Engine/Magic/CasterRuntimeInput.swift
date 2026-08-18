// Cast input (issue #470, roadmap item 19.7): one frame of held buttons turned
// into the begin and release edges the cast loop acts on.
//
// A satellite of `CasterRuntime` so that file stays under the strict-lint
// length cap, and because the two halves are genuinely different: the runtime
// owns what a cast does, this owns when the player asked for one.
//
// ## Which button is which hand
//
// The same two buttons melee and archery already use, routed by what the hand
// holds — exactly the rule `ArcheryIntent` states for the bow: "it is the same
// button: with a bow equipped the attack press draws instead of swinging". A
// spell readied in the right hand takes the attack button; a spell readied in
// the left takes the block button. Nothing new is bound, and a hand holding no
// spell leaves its button to melee.
//
// Held levels rather than presses, because casting is a hold: UESP describes
// both shapes that way — "Some spells will trigger immediately upon being cast
// and can be maintained as long as held. Others require holding to charge the
// spell and releasing to cast it."
// (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>)
//
// Documented in docs/engine/magic.md.

import Foundation

/// One frame of cast intent, filled from the same drained camera input
/// `MeleeIntent` and `ArcheryIntent` are.
nonisolated struct CastingIntent: Equatable, Sendable {
    /// Block button held, which the left hand takes when it holds a spell.
    var leftHeld = false
    /// Attack button held, which the right hand takes when it holds a spell.
    var rightHeld = false
    /// Seconds since the previous frame, for the charge and drain clocks.
    var deltaTime: Float = 0

    static let still = CastingIntent()

    func isHeld(_ hand: SpellHand) -> Bool {
        switch hand {
        case .left: leftHeld
        case .right: rightHeld
        }
    }
}

extension CasterRuntime {
    /// Takes one frame of cast intent and advances both hands.
    ///
    /// Edges rather than levels: a button that went down begins a cast and one
    /// that came up releases it, so a held button does not restart the charge
    /// sixty times a second. A hand holding no spell is left alone entirely,
    /// which is what leaves its button to melee.
    func acceptFrame(_ intent: CastingIntent, on caster: ActorValueHolder) {
        let readied = spellbook.state(of: caster)
        for hand in SpellHand.allCases {
            guard readied.spell(in: hand) != nil else {
                releaseIfHeld(hand, on: caster)
                continue
            }
            let held = intent.isHeld(hand)
            if held, !wasHeld(hand, on: caster.key) {
                begin(hand, on: caster)
            } else if !held, wasHeld(hand, on: caster.key) {
                release(hand, on: caster)
            }
            setHeld(hand, held, on: caster.key)
        }
        advance(delta: intent.deltaTime, on: caster)
    }

    /// Drops a cast whose hand no longer holds a spell — an unequip mid-cast,
    /// which is otherwise a charge nothing can ever release.
    private func releaseIfHeld(_ hand: SpellHand, on caster: ActorValueHolder) {
        guard wasHeld(hand, on: caster.key) || phase(of: hand, on: caster.key).isCasting
        else { return }
        cancel(hand, on: caster)
        setHeld(hand, false, on: caster.key)
    }
}
