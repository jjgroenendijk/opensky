// Combat loop checks on the real install that the synthetic suites cannot make:
// the vanilla player graph declares the hit-reaction event and variables, the
// three reaction clips decode against a real skeleton, the loop's per-step cost
// with real combat GMSTs and a crowd, and a Whiterun-area hostile runs the full
// loop against the player offscreen. The app's entry points are the milestone
// gate's job, not this suite's.

import Foundation
import Metal
@testable import OpenSkyActorsInterface
@testable import OpenSkyBehavior
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyWorld
import simd
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct CombatLoopRealDataTests {
    /// Actors the budget measurement runs over. More than a room holds, so the
    /// number is a ceiling rather than a typical case.
    private static let crowdSize = 32

    /// Steps the budget measurement averages over.
    private static let budgetSteps = 600

    /// An OpenSky budget for one fixed loop step, in milliseconds. The loop runs
    /// beside physics, animation, and Papyrus, and does little work, so a
    /// generous tenth of a millisecond is tripped only by a real regression.
    private static let stepBudgetMS = 0.1

    // MARK: - The graph

    /// Every name the loop raises has to resolve on the vanilla player graph.
    /// This is the one that fails loudly if a census reading was wrong.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func vanillaGraphAcceptsTheCensusNamedRecoilNames() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let bridge = try Self.bridge(root: root)

        for name in [CombatGraphNames.recoilStart, CombatGraphNames.recoilStop] {
            bridge.raise(name)
        }
        bridge.write(.bool(false), to: CombatGraphNames.isRecoiling)
        bridge.write(.real(0), to: CombatGraphNames.recoilMagnitude)

        #expect(
            bridge.status.missingEvents.isEmpty,
            "the vanilla graph declares no home for \(bridge.status.missingEvents)"
        )
        #expect(
            bridge.status.missingVariables.isEmpty,
            "the vanilla graph declares no home for \(bridge.status.missingVariables)"
        )
        #expect(bridge.status.raisedEvents.contains(CombatGraphNames.recoilStart))
    }

    // MARK: - The clips

    /// The three reaction clips decode against a real skeleton. Vanilla ships no
    /// unarmed stagger, so this also proves the one-handed substitute binds.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func everyReactionClipDecodesAgainstAVanillaSkeleton() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let skeletonMeshPath = ActorAnimationClipLoader.characterRoot
            + "character assets\\skeleton.nif"

        for reaction in CombatActorClip.allCases {
            let path = ActorAnimationClipLoader.animationPath(for: reaction)
            let clip = try ActorAnimationClipLoader.clip(
                skeletonMeshPath: skeletonMeshPath,
                animationPath: path,
                readHKX: { try HKXFile(data: vfs.contents(forPath: $0)) }
            )
            #expect(clip.animation.duration > 0, "\(path) decodes to a zero-length clip")
            #expect(!clip.skeleton.boneNames.isEmpty, "\(path) bound to a rig with no bones")
            // The clip has to move bones the rig actually names, or the actor
            // would stand in its bind pose through the whole reaction.
            let posed = clip.namedWorldTransforms(at: 0)
            #expect(posed?.isEmpty == false, "\(path) sampled to no pose at all")
            #expect(
                ActorAnimationClipLoader.holdSeconds(for: reaction) > 0,
                "\(reaction) holds for no time"
            )
        }
    }

    // MARK: - The budget

    /// One fixed step of the loop, over the install's own combat GMSTs and a
    /// crowd of actors, measured and reported.
    ///
    /// The report goes to gitignored `logs/` and is linked from the PR; item
    /// 15.9 reads the number beside the 15.2 physics gate.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    @MainActor
    func theLoopStepStaysInsideItsBudgetWithACrowd() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let settings = CombatSettings.resolve(store: GameSettingLoader.load(root: root))
        // The install's numbers, not the fallbacks, or the measurement is of a
        // session that never loaded game data.
        #expect(settings.combatDistance.source != "vanilla Skyrim.esm value")

        let world = Self.crowd(count: Self.crowdSize)
        let runtime = CombatLoopRuntime(settings: settings, world: world)

        let start = Date()
        for _ in 0 ..< Self.budgetSteps {
            runtime.advance(by: CombatLoopRuntime.fixedStepSeconds)
        }
        let perStepMS = Date().timeIntervalSince(start) * 1000 / Double(Self.budgetSteps)

        #expect(runtime.state.isPlayerInCombat)
        #expect(
            perStepMS < Self.stepBudgetMS,
            "combat loop step \(perStepMS) ms over the \(Self.stepBudgetMS) ms budget"
        )
        try Self.report(perStepMS: perStepMS, hits: runtime.incomingHitCount)
    }

    // MARK: - The whole loop, on a real hostile

    /// A Whiterun-area hostile runs the loop against the player offscreen:
    /// detect, engage, attack, lose, search, give up, and return to its package.
    /// Perception runs first, as in the session. Only the order of transitions
    /// is checked, not their timing. There is no mover, so the guard fights
    /// from its placed position; its approach commands are counted.
    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func aWhiterunHostileRunsTheWholeLoopAgainstThePlayer() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let scene = try WhiterunGuardFixture.buildCell(
            root: root, device: #require(RealDataEnvironment.device)
        )
        let located = try #require(
            WhiterunGuardFixture.locate(
                in: scene, templates: WhiterunGuardFixture.templates(root: root)
            ),
            Comment(rawValue: "no \(WhiterunGuardFixture.editorIDPrefix) ACHR in "
                + "\(WhiterunGuardFixture.worldspace)")
        )
        let store = GameSettingLoader.load(root: root)
        let fight = WhiterunFight(located: located, scene: scene, store: store)

        let start = DispatchTime.now().uptimeNanoseconds
        fight.walkIn()
        fight.hide()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000

        #expect(fight.phases.first == .idle)
        #expect(fight.phases.contains(.approaching), "the guard never engaged")
        #expect(fight.phases.contains(.contact), "the guard never landed a contact frame")
        #expect(fight.phases.contains(.searching), "the guard never searched")
        #expect(fight.phases.last == .disengaged, "the guard never gave up")
        #expect(fight.combatWorld.damage[.player, default: 0] > 0)
        #expect(fight.combatWorld.packageResumes.contains(located.key))
        #expect(!fight.combat.state.isPlayerInCombat)

        let perStepMS = elapsed / Double(fight.steps)
        #expect(
            perStepMS < Self.stepBudgetMS,
            "combat loop step \(perStepMS) ms over the \(Self.stepBudgetMS) ms budget"
        )
        let order = fight.phases.map(\.rawValue).joined(separator: " -> ")
        print("[INFO] \(located.editorID) (\(located.key)) at \(located.actor.placement.position)")
        print("[INFO] phases \(order) over \(fight.steps) fixed steps, "
            + "\(String(format: "%.4f", perStepMS)) ms per step offscreen")
        print("[INFO] \(fight.combatWorld.damage[.player, default: 0]) damage taken, "
            + "\(fight.combatWorld.moveRequests.count) path requests refused")
        try Self.report(
            perStepMS: perStepMS,
            hits: fight.combat.incomingHitCount,
            actors: 1,
            steps: fight.steps,
            file: "combat-whiterun-fight.log"
        )
    }

    // MARK: - Helpers

    /// The crowd the budget measurement runs over: a line of hostile actors
    /// that have all seen the player, the nearest inside reach so the number
    /// includes the blow-landing path rather than only the idle one.
    @MainActor
    private static func crowd(count: Int) -> FakeCombatWorld {
        let world = FakeCombatWorld()
        world.actors = (0 ..< count).map { index in
            CombatActorObservation(
                key: .generated(UInt64(index + 1)),
                feet: SIMD3(60 + Float(index) * 40, 0, 0),
                name: "actor \(index)"
            )
        }
        for actor in world.actors {
            world.hostility[actor.key] = .hostile
            world.awareness[actor.key] = .detected(at: world.player.feet)
            world.weapons[actor.key] = MeleeWeaponProfile(damage: 10, reach: 1)
        }
        return world
    }

    private static func bridge(root: GameDataRoot) throws -> LocomotionBridge {
        let graph = try PlayerBehaviorGraph.load(
            fileSystem: VirtualFileSystem(root: root)
        ).instance
        let bridge = LocomotionBridge(
            configuration: PlayerMovementConfiguration.resolve(
                store: GameSettingLoader.load(root: root),
                movementTypes: MovementTypeLoader.load(root: root)
            ),
            graph: graph
        )
        graph.activate()
        return bridge
    }

    /// Writes the measurement where a PR can link it. Gitignored, per
    /// AGENTS.md: a run artefact is never committed.
    private static func report(
        perStepMS: Double,
        hits: Int,
        actors: Int = crowdSize,
        steps: Int = budgetSteps,
        file: String = "combat-loop-budget.log"
    ) throws {
        let text = """
        OpenSky combat loop budget (issues #374 and #424)

        actors:          \(actors)
        steps:           \(steps)
        per-step:        \(String(format: "%.4f", perStepMS)) ms
        budget:          \(stepBudgetMS) ms
        blows landed:    \(hits)
        """
        // Through the shared helper rather than a relative path: the test host's
        // working directory is not the checkout, so `logs/...` resolves to the
        // filesystem root and the write fails.
        try PlayerBodyFixture.write(text, to: file)
    }
}
