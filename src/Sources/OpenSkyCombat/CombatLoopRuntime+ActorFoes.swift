// NPC against NPC: an actor fights another actor it attacks on sight once it detects it,
// and fights back an actor that fights it. The player's side is chosen as before. See
// docs/engine/combat.md#npc-foes.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import simd

extension CombatLoopRuntime {
    /// How often the hostile NPC pairs are found again. An OpenSky value, the shortest
    /// detection pass interval (`fDetectionUpdateTimeMin`).
    static let foeScanSeconds: Float = 1
    /// How far apart two NPCs may be to count as foes. An OpenSky value: the distance at
    /// which a fight breaks off.
    static let foeScanRange: Float = 4096

    /// Whether `key` fights the player or the player's allies, or is one of those allies.
    /// An actor with no target yet counts, as a foe of the player.
    func fightsPlayerSide(_ key: ReferenceKey) -> Bool {
        guard let target = targets[key], commanders[key] != .player else { return true }
        return target == .player || commanders[target] == .player
    }

    /// Finds again, once a second, each pair of living NPCs within the range where the
    /// first attacks the second on sight. The player's allies are left out on both sides.
    func scanFoes(_ actors: [CombatActorObservation], world: any CombatLoopWorld) {
        foeScanWait -= Self.fixedStepSeconds
        guard foeScanWait <= 0 else { return }
        foeScanWait = Self.foeScanSeconds
        let player = world.combatPlayer.key
        let living = actors.filter {
            !$0.isDead && $0.key != player && commanders[$0.key] != player
        }
        var pairs: Set<CombatFoePair> = []
        for observer in living {
            for target in living where target.key != observer.key {
                guard
                    simd_distance(observer.feet, target.feet) <= Self.foeScanRange,
                    world.combatIsHostile(observer.key, toward: target.key)
                else { continue }
                pairs.insert(CombatFoePair(observer: observer.key, target: target.key))
            }
        }
        foePairs = pairs
    }

    /// The NPC each actor fights: the nearest one it attacks on sight and has detected,
    /// or one that fights it, unless it counts that one an ally or a friend. A
    /// fight back needs no detection; the actor is attacked.
    func actorFoes(
        among actors: [CombatActorObservation], world: any CombatLoopWorld
    ) -> [ReferenceKey: MeleeTarget] {
        retaliating = []
        let player = world.combatPlayer.key
        let living = Dictionary(
            actors.filter { !$0.isDead && $0.key != player && commanders[$0.key] != player }
                .map { ($0.key, $0) }
        ) { first, _ in first }
        var options: [ReferenceKey: [CombatActorObservation]] = [:]
        var seen: Set<CombatFoePair> = []
        for pair in foePairs.sorted() {
            guard
                let target = living[pair.target], living[pair.observer] != nil,
                world.combatAwareness(of: pair.observer, toward: pair.target).isDetected
            else { continue }
            options[pair.observer, default: []].append(target)
            seen.insert(pair)
        }
        var attacked: Set<ReferenceKey> = []
        for (attacker, victim) in targets.sorted(by: { $0.key < $1.key }) {
            guard
                let attacking = living[attacker], living[victim] != nil,
                behaviors[attacker]?.isEngaged == true,
                world.combatReaction(of: victim, toward: attacker).map(\.isFriendly) != true
            else { continue }
            if options[victim]?.contains(where: { $0.key == attacker }) != true {
                options[victim, default: []].append(attacking)
                attacked.insert(victim)
            }
        }
        addAssistedFoes(to: &options, attacked: &attacked, living: living)
        var foes: [ReferenceKey: MeleeTarget] = [:]
        for (key, choices) in options {
            guard
                let actor = living[key],
                let foe = CombatAllyRule.nearest(
                    choices.map { MeleeTarget(key: $0.key, feet: $0.feet, capsule: $0.capsule) },
                    to: actor.feet
                )
            else { continue }
            foes[key] = foe
            if attacked.contains(key), !seen.contains(CombatFoePair(
                observer: key,
                target: foe.key
            )) {
                retaliating.insert(key)
            }
        }
        return foes
    }
}

extension CombatLoopRuntime {
    /// A helper fights the NPC its ally fights, unseen, while both live.
    private func addAssistedFoes(
        to options: inout [ReferenceKey: [CombatActorObservation]],
        attacked: inout Set<ReferenceKey>,
        living: [ReferenceKey: CombatActorObservation]
    ) {
        for (helper, foe) in npcAssists.sorted(by: { $0.key < $1.key }) {
            guard living[helper] != nil, let target = living[foe] else {
                npcAssists[helper] = nil
                continue
            }
            guard options[helper]?.contains(where: { $0.key == foe }) != true else { continue }
            options[helper, default: []].append(target)
            attacked.insert(helper)
        }
    }
}

extension ActorReaction {
    /// Ally and Friend: a target the observer does not fight back.
    var isFriendly: Bool {
        self == .ally || self == .friend
    }
}
