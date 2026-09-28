// Env-gated combat loop over the user's own Skyrim SE install (read-only
// external input, never committed — AGENTS.md "Legal & IP"), issues #374 and
// #424.
//
// The synthetic suites prove the loop's arithmetic against a fake world, and
// every name and path they use is quoted from the census. The claims they cannot
// make are the ones here:
//
// 1. the *vanilla* player graph declares the hit-reaction event and variables
//    the loop raises — a census name the graph refuses would leave every
//    synthetic test green and the reaction dead;
// 2. the three reaction clip paths exist in this install and decode against a
//    real character skeleton, including the documented substitution of a
//    one-handed stagger for the unarmed one vanilla does not ship;
// 3. the loop's own per-step cost, measured against the install's real combat
//    GMSTs and a crowd of actors, so item 15.9 has a number to put beside the
//    15.2 physics gate rather than an assumption;
// 4. item 16.7's own acceptance line — a real Whiterun-area hostile running the
//    whole loop against the player over the real city geometry, offscreen, with
//    the per-step cost recorded.
//
// What this deliberately does *not* do is drive the app's shipping entry points
// end to end. That route is the milestone gate's (item 15.9, issue #198, and
// item 16.8 for M16); duplicating half of it here would give two partial answers
// instead of one whole one.
//
// Skips automatically when OPENSKY_DATA_ROOT is unset. Run with
// `make realtest T='CombatLoopRealDataTests/vanillaGraphAcceptsTheCensusNamedRecoilNames()'`.

import Foundation
import Metal
@testable import opensky
import simd
import Testing

struct CombatLoopRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// The device the Whiterun cell is built with. Nil on a machine with no
    /// Metal 4 GPU, which skips the one case that needs geometry.
    private static let device: MTLDevice? = {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    /// Actors the budget measurement runs over. More than a room holds, so the
    /// number is a ceiling rather than a typical case.
    private static let crowdSize = 32

    /// Steps the budget measurement averages over.
    private static let budgetSteps = 600

    /// What one fixed step of the loop may cost, milliseconds.
    ///
    /// An OpenSky budget, chosen the way the 15.2 step budget was: the loop runs
    /// once per fixed step beside physics, animation and the Papyrus VM, and a
    /// tenth of a millisecond leaves the frame to the systems that actually
    /// draw. It is deliberately generous — the loop derives a state over a small
    /// array and advances one clock — so a regression that trips it is a real
    /// one.
    private static let stepBudgetMS = 0.1

    // MARK: - The graph

    /// Every name the loop raises has to resolve on the vanilla player graph.
    /// This is the one that fails loudly if a census reading was wrong.
    @Test(.enabled(if: Self.dataRoot != nil))
    func vanillaGraphAcceptsTheCensusNamedRecoilNames() throws {
        let root = try #require(Self.dataRoot)
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

    /// The three reaction clips exist in this install and decode against a real
    /// character skeleton.
    ///
    /// The stagger is the interesting one: vanilla ships no unarmed stagger, so
    /// the loader substitutes the one-handed small stagger, and this is what
    /// proves the substitution actually binds to the same rig rather than being
    /// a plausible-looking path.
    @Test(.enabled(if: Self.dataRoot != nil))
    func everyReactionClipDecodesAgainstAVanillaSkeleton() throws {
        let root = try #require(Self.dataRoot)
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
    @Test(.enabled(if: Self.dataRoot != nil))
    @MainActor
    func theLoopStepStaysInsideItsBudgetWithACrowd() throws {
        let root = try #require(Self.dataRoot)
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

    /// Item 16.7's acceptance line: a Whiterun-area hostile runs the loop
    /// against the player — detect, engage, attack for real damage, lose the
    /// player, search, give up and be handed back to its package — offscreen,
    /// over the real city geometry and the install's own GMSTs, with the frame
    /// budget recorded.
    ///
    /// The two runtimes are wired the way the session wires them: perception is
    /// advanced first over the real static collision, and what it concluded is
    /// what the fight is told. Nothing is asserted about *when* a transition
    /// falls — that depends on where this install's guard is standing — only
    /// that the whole sequence happens and in that order.
    ///
    /// The mover is deliberately absent. This is the decision layer's evidence,
    /// and 16.4 has its own; a refused path is the honest answer here, and the
    /// guard fights from where the level designer put it while the player walks
    /// in. The approach commands it issued are counted and printed rather than
    /// ignored.
    @Test(.enabled(if: Self.dataRoot != nil && Self.device != nil))
    @MainActor
    func aWhiterunHostileRunsTheWholeLoopAgainstThePlayer() throws {
        let root = try #require(Self.dataRoot)
        let scene = try WhiterunGuardFixture.buildCell(
            root: root, device: #require(Self.device)
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
