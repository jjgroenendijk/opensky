// Wards around a landed spell: the defences a hit runs, a ward that breaks, and the
// ward's strength coming back. UESP "Skyrim:Ward": "Whenever HP of the Ward drops
// below maximum value, it will immediately start regenerating it", and a spell that
// breaks a ward does no damage, "but you will be staggered".
// See docs/engine/spell-delivery.md#defences.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

extension MagicCoordinator.WardShields {
    /// Ward strength restored per second. OpenSky's choice: Lesser Ward's magnitude,
    /// so a ward refills in about a second, as it charges.
    static let wardRecoveryPerSecond: Float = 40
    /// How long a broken ward answers `IsWardState` 2.
    static let brokenWardSeconds: Float = 1
    /// The stagger a broken ward gives its holder.
    static let wardBreakStagger: Float = 1

    /// `IsWardState` values. Taken from the `OnWardHit` statuses; the condition's own
    /// page gives none.
    enum WardState: Int32, Sendable {
        case none = 0
        case absorbing = 1
        case broken = 2
    }

    /// The absorption roll, in 0 ..< 100, from a fixed seed. A test replaces it.
    static func seededDefenceRoll() -> () -> Float {
        { [stream = RandomStream(seed: 0x5350_4446)] in stream.float(in: 0 ..< 100) }
    }

    func spellHitDefences() -> SpellHitDefences {
        var defences = SpellHitDefences()
        defences.absorptionRoll = coordinator.spellDefenceRoll
        let world = coordinator.world
        defences.wardFaces = { target, caster in world.actor(target, faces: caster) }
        defences.reaches = { target, impact in world.point(impact, canSee: target) }
        defences.wardPowerCap = { [weak coordinator] holder in
            coordinator?.wardShields.wardPowerCap(of: holder) ?? .infinity
        }
        defences.wardMagickaShare = { holder in
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
            coordinator.brokenWardSeconds[key] = Self.brokenWardSeconds
            coordinator.pendingCommands.append(.stagger(key, magnitude: Self.wardBreakStagger))
            guard let holder = coordinator.world.actorValueHolder(for: key) else { continue }
            for hand in SpellHand.allCases {
                coordinator.caster?.cancel(hand, on: holder)
            }
        }
    }

    /// Restores lost ward strength and runs the broken-ward clocks.
    func recoverWards(delta: Float, over holders: [ActorValueHolder]) {
        guard delta > 0, let effects = coordinator.effects else { return }
        for holder in holders {
            effects.values.restore(
                at: SpellHitApplication.wardPowerActorValue,
                by: Self.wardRecoveryPerSecond * delta,
                on: holder
            )
        }
        coordinator.brokenWardSeconds = coordinator.brokenWardSeconds
            .mapValues { $0 - delta }
            .filter { $0.value > 0 }
    }

    /// The most ward power `holder` may use: a share of its strongest running ward.
    func wardPowerCap(of holder: ActorValueHolder) -> Float {
        guard let effects = coordinator.effects else { return .infinity }
        let strongest = effects.active(on: holder)
            .filter { effects.rule(of: $0) == .accumulate }
            .flatMap(\.values)
            .filter { $0.index == SpellHitApplication.wardPowerActorValue }
            .map(\.magnitude)
            .max()
        guard let strongest else { return .infinity }
        let skill = ActorValueIdentity.index(named: "Restoration")
            .flatMap { effects.values.value(at: $0, on: holder) } ?? 0
        return coordinator.rules.world.wardPowerCap(strongest: strongest, skill: skill)
    }

    /// The ward state of `key` as `IsWardState` reads it.
    func wardState(of key: ReferenceKey) -> WardState {
        if coordinator.brokenWardSeconds[key] != nil {
            return .broken
        }
        guard
            let holder = coordinator.world.actorValueHolder(for: key),
            let power = coordinator.effects?.values.value(
                at: SpellHitApplication.wardPowerActorValue,
                on: holder
            )
        else { return .none }
        return power > 0 ? .absorbing : .none
    }
}
