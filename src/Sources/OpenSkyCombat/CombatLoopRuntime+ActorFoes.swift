// NPC against NPC: an actor fights another actor it attacks on sight once it detects it,
// and fights back an actor that fights it. The player's side is chosen as before. See
// docs/engine/combat.md#npc-foes.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import simd

extension CombatLoopRuntime {
    /// After each detection pass the next comes a random 1 to 2 seconds later
    /// (docs/engine/combat.md#npc-foes). The game waits 2.5 to 5 seconds in a complex
    /// scene; OpenSky has no such test yet.
    static let foeScanSeconds: ClosedRange<Float> = 1 ... 2
    /// How far apart two NPCs may be to count as foes. An OpenSky value: the distance at
    /// which a fight breaks off.
    static let foeScanRange: Float = 4096

    /// Whether `key` fights the player or the player's allies, or is one of those allies.
    /// An actor with no target yet counts, as a foe of the player.
    func fightsPlayerSide(_ key: ReferenceKey) -> Bool {
        guard let target = targets[key], commanders[key] != .player else { return true }
        return target == .player || commanders[target] == .player
    }

    /// Each living NPC finds, on its own detection pass, the NPCs within the range that it
    /// attacks on sight. The player's allies are left out on both sides.
    func scanFoes(_ actors: [CombatActorObservation], world: any CombatLoopWorld) {
        let player = world.combatPlayer.key
        let living = actors.filter {
            !$0.isDead && $0.key != player && commanders[$0.key] != player
        }
        let keys = Set(living.map(\.key))
        for observer in living {
            let wait = (foeScanWaits[observer.key] ?? 0) - Self.fixedStepSeconds
            guard wait <= 0 else {
                foeScanWaits[observer.key] = wait
                continue
            }
            let range = Self.foeScanSeconds
            let unit = Float(foeScanRandom.next() % 1001) / 1000
            foeScanWaits[observer.key] = range
                .lowerBound + (range.upperBound - range.lowerBound) * unit
            scannedFoes[observer.key] = Set(living.compactMap { target in
                guard
                    target.key != observer.key,
                    simd_distance(observer.feet, target.feet) <= Self.foeScanRange,
                    world.combatIsHostile(observer.key, toward: target.key)
                else { return nil }
                return CombatFoePair(observer: observer.key, target: target.key)
            })
        }
        foeScanWaits = foeScanWaits.filter { keys.contains($0.key) }
        scannedFoes = scannedFoes.filter { keys.contains($0.key) }
        aggroFoePairs = aggroFoePairs.filter {
            keys.contains($0.observer) && keys.contains($0.target)
        }
        let scanned = scannedFoes.values.reduce(into: Set<CombatFoePair>()) { $0.formUnion($1) }
        foePairs = scanned.filter { keys.contains($0.target) }.union(aggroFoePairs)
    }

    /// The NPC each actor fights: the nearest one it attacks on sight and has detected,
    /// or one that fights it, unless it counts that one an ally or a friend. A
    /// fight back needs no detection; the actor is attacked.
    func actorFoes(
        among actors: [CombatActorObservation], world: any CombatLoopWorld
    ) -> [ReferenceKey: MeleeTarget] {
        FoeScan(owner: self).actorFoes(among: actors, world: world)
    }
}

/// One NPC's last target pick, and the seconds until it picks again.
nonisolated struct CombatTargetPick: Equatable, Sendable {
    static let keptSeconds: Float = 1
    static let changedSeconds: Float = 3

    let target: ReferenceKey
    var wait: Float
}

extension ActorReaction {
    /// Ally and Friend: a target the observer does not fight back.
    var isFriendly: Bool {
        self == .ally || self == .friend
    }
}

extension CombatLoopRuntime {
    /// Finds the foes each actor fights among the observed actors.
    struct FoeScan {
        let owner: CombatLoopRuntime

        func actorFoes(
            among actors: [CombatActorObservation], world: any CombatLoopWorld
        ) -> [ReferenceKey: MeleeTarget] {
            owner.retaliating = []
            let player = world.combatPlayer.key
            let living = Dictionary(
                actors
                    .filter { !$0.isDead && $0.key != player && owner.commanders[$0.key] != player }
                    .map { ($0.key, $0) }
            ) { first, _ in first }
            var options: [ReferenceKey: [CombatActorObservation]] = [:]
            var seen: Set<CombatFoePair> = []
            for pair in owner.foePairs.sorted() {
                guard
                    let target = living[pair.target], living[pair.observer] != nil,
                    world.combatAwareness(of: pair.observer, toward: pair.target).isDetected
                else { continue }
                options[pair.observer, default: []].append(target)
                seen.insert(pair)
            }
            var attacked: Set<ReferenceKey> = []
            for (attacker, victim) in owner.targets.sorted(by: { $0.key < $1.key }) {
                guard
                    let attacking = living[attacker], living[victim] != nil,
                    owner.behaviors[attacker]?.isEngaged == true,
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
                        choices
                            .map { MeleeTarget(key: $0.key, feet: $0.feet, capsule: $0.capsule) },
                        to: actor.feet
                    )
                else { continue }
                foes[key] = foe
                if attacked.contains(key), !seen.contains(CombatFoePair(
                    observer: key,
                    target: foe.key
                )) {
                    owner.retaliating.insert(key)
                }
            }
            return foes
        }

        /// A helper fights the NPC its ally fights, unseen, while both live.
        func addAssistedFoes(
            to options: inout [ReferenceKey: [CombatActorObservation]],
            attacked: inout Set<ReferenceKey>,
            living: [ReferenceKey: CombatActorObservation]
        ) {
            for (helper, foe) in owner.npcAssists.sorted(by: { $0.key < $1.key }) {
                guard living[helper] != nil, let target = living[foe] else {
                    owner.npcAssists[helper] = nil
                    continue
                }
                guard options[helper]?.contains(where: { $0.key == foe }) != true else { continue }
                options[helper, default: []].append(target)
                attacked.insert(helper)
            }
        }
    }
}
