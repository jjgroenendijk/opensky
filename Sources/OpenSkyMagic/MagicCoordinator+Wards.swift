// Wards around a landed spell: the defences a hit runs, a ward that breaks, and the
// ward's strength coming back. UESP "Skyrim:Ward": "Whenever HP of the Ward drops
// below maximum value, it will immediately start regenerating it", and a spell that
// breaks a ward does no damage, "but you will be staggered".
// See docs/engine/spell-delivery.md#defences.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

extension MagicCoordinator {
    /// Ward strength restored per second. OpenSky's choice: Lesser Ward's magnitude,
    /// so a ward refills in about a second, as it charges.
    public static let wardRecoveryPerSecond: Float = 40
    /// How long a broken ward answers `IsWardState` 2.
    public static let brokenWardSeconds: Float = 1
    /// The stagger a broken ward gives its holder.
    public static let wardBreakStagger: Float = 1

    /// `IsWardState` values. Taken from the `OnWardHit` statuses; the condition's own
    /// page gives none.
    public enum WardState: Int32, Sendable {
        case none = 0
        case absorbing = 1
        case broken = 2
    }

    func spellHitDefences() -> SpellHitDefences {
        var defences = SpellHitDefences()
        defences.absorptionRoll = spellDefenceRoll
        defences.wardFaces = { [world] target, caster in world.actor(target, faces: caster) }
        defences.reaches = { [world] target, impact in world.point(impact, canSee: target) }
        defences.wardMagickaShare = { [world] holder in
            world.perkModified(
                0, at: .modWardMagickaAbsorptionPct, on: holder,
                subjects: PerkEvaluationSubjects(owner: holder), seams: ConditionContext()
            )
        }
        return defences
    }

    /// A broken ward staggers its holder and ends the holder's casts.
    func breakWards(_ holders: [ReferenceKey]) {
        for key in holders {
            brokenWardSeconds[key] = Self.brokenWardSeconds
            pendingCommands.append(.stagger(key, magnitude: Self.wardBreakStagger))
            guard let holder = world.actorValueHolder(for: key) else { continue }
            for hand in SpellHand.allCases {
                caster?.cancel(hand, on: holder)
            }
        }
    }

    /// Restores lost ward strength and runs the broken-ward clocks.
    func recoverWards(delta: Float, over holders: [ActorValueHolder]) {
        guard delta > 0, let effects else { return }
        for holder in holders {
            effects.values.restore(
                at: SpellHitApplication.wardPowerActorValue,
                by: Self.wardRecoveryPerSecond * delta,
                on: holder
            )
        }
        brokenWardSeconds = brokenWardSeconds
            .mapValues { $0 - delta }
            .filter { $0.value > 0 }
    }

    /// The ward state of `key` as `IsWardState` reads it.
    public func wardState(of key: ReferenceKey) -> WardState {
        if brokenWardSeconds[key] != nil {
            return .broken
        }
        guard
            let holder = world.actorValueHolder(for: key),
            let power = effects?.values.value(
                at: SpellHitApplication.wardPowerActorValue,
                on: holder
            )
        else { return .none }
        return power > 0 ? .absorbing : .none
    }
}
