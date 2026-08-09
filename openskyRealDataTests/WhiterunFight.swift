// One whole fight against a real Whiterun guard (issue #424, roadmap item
// 16.7), driven step by step so `CombatLoopRealDataTests` can assert on the
// sequence rather than on an end state.
//
// Support for the gated suite beside it, in its own file for the lint file cap.
// The two runtimes are wired the way `GameViewController` wires them: perception
// is advanced over the real static collision first, and what it concluded is
// what the fight is told. Nothing here reads a clock, so the sequence is a pure
// function of the step counts below.
//
// Read-only external input: the guard's placement and the city's collision come
// out of the install and stay there (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import simd

@MainActor
final class WhiterunFight {
    /// How far out the player starts and how far each stride carries them,
    /// world units — the same approach the perception suite walks.
    static let approachStart: Float = 2800
    static let approachStride: Float = 100
    /// Fixed steps spent at each stride, which is what turns an approach into a
    /// sequence of states rather than one jump.
    static let stepsPerStride = 20
    /// Where the player goes to break the guard's line of sight: far enough
    /// that no sense reaches, which is the honest way to hide from a pass whose
    /// only occluders are the city's own collision.
    static let hidingDistance: Float = 20000
    /// Steps spent hidden. Long enough for the level to decay, the search to run
    /// its stated time and the give-up to land.
    static let hidingSteps = 1800

    let combat: CombatLoopRuntime
    let combatWorld: FakeCombatWorld
    /// Every distinct phase the guard passed through, in order.
    private(set) var phases: [CombatBehaviorPhase] = []
    /// Fixed steps run, which is what the per-step cost divides by.
    private(set) var steps = 0

    private let perception: PerceptionRuntime
    private let perceptionWorld: FakePerceptionWorld
    private let guardKey: ReferenceKey
    private let guardFeet: SIMD3<Float>
    private let heading: SIMD3<Float>

    init(located: WhiterunGuardFixture.LocatedGuard, scene: CellScene, store: GameSettingStore) {
        guardKey = located.key
        guardFeet = located.actor.placement.position
        let facing = located.actor.placement.rotation.z
        heading = SIMD3(cos(facing), sin(facing), 0)

        let observer = PerceptionObserver(
            key: located.key,
            feet: guardFeet,
            facing: facing,
            isExterior: true,
            name: located.editorID
        )
        perceptionWorld = FakePerceptionWorld(observers: [observer])
        perceptionWorld.blocked = WhiterunGuardFixture.blockedPredicate(
            against: scene.staticCollision
        )
        perception = PerceptionRuntime(
            settings: DetectionSettings.resolve(store: store), world: perceptionWorld
        )

        combatWorld = FakeCombatWorld()
        combatWorld.actors = [CombatActorObservation(
            key: located.key,
            feet: guardFeet,
            facing: facing,
            scale: located.actor.scale,
            name: located.editorID
        )]
        // The guard is already angry, which is the panel toggle's state and the
        // one 16.7 widens entry from: what this case is evidence for is that
        // *perceiving* the player is what starts the fight.
        combatWorld.hostility[located.key] = .hostile
        combatWorld.weapons[located.key] = MeleeWeaponProfile(damage: 10, reach: 1)
        // No mover in this harness, so every path request is refused and the
        // guard fights from where the level designer put it.
        combatWorld.movementSucceeds = false
        combat = CombatLoopRuntime(
            settings: CombatSettings.resolve(store: store),
            world: combatWorld
        )
    }

    /// Walks the player in along the guard's facing, one stride at a time,
    /// until they are standing inside its reach.
    func walkIn() {
        var distance = Self.approachStart
        while distance > 0 {
            advance(playerAt: guardFeet + heading * distance, steps: Self.stepsPerStride)
            distance -= Self.approachStride
        }
        // A few full attack cycles at contact range, so the blows the loop lands
        // are the thing being measured rather than the last stride's leftovers.
        advance(playerAt: guardFeet + heading * 20, steps: Self.stepsPerStride * 12)
    }

    /// Takes the player out of every sense's reach and holds them there while
    /// the guard's level decays, it searches, and it gives up.
    func hide() {
        advance(
            playerAt: guardFeet + heading * Self.hidingDistance, steps: Self.hidingSteps
        )
    }

    /// One block of fixed steps with the player standing at `feet`.
    private func advance(playerAt feet: SIMD3<Float>, steps count: Int) {
        perceptionWorld.targets = [PerceptionTarget(
            key: .player, feet: feet, gait: .walk, name: "Player"
        )]
        combatWorld.player = MeleeAttacker(key: .player, feet: feet, facing: 0)
        for _ in 0 ..< count {
            perception.advance(by: PerceptionRuntime.fixedStepSeconds)
            let pair = perception.state(observer: guardKey, target: .player)
            combatWorld.awareness[guardKey] = CombatAwareness(
                state: pair.state, lastKnownPosition: pair.lastKnownPosition
            )
            combat.advance(by: CombatLoopRuntime.fixedStepSeconds)
            steps += 1
            let phase = combat.phase(of: guardKey) ?? .idle
            if phases.last != phase {
                phases.append(phase)
            }
        }
    }
}
