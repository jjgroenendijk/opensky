// Env-gated combat loop over the user's own Skyrim SE install (read-only
// external input, never committed — AGENTS.md "Legal & IP"), issue #374.
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
//    15.2 physics gate rather than an assumption.
//
// What this deliberately does *not* do is stream a vanilla interior and fight in
// it. That route is the milestone gate's (item 15.9, issue #198), which drives
// the shipping entry points end to end; duplicating half of it here would give
// two partial answers instead of one whole one.
//
// Skips automatically when OPENSKY_DATA_ROOT is unset. Run with
// `make realtest T='CombatLoopRealDataTests/vanillaGraphAcceptsTheCensusNamedRecoilNames()'`.

import Foundation
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

        let world = CrowdedCombatWorld(count: Self.crowdSize)
        let runtime = CombatLoopRuntime(settings: settings, world: world)
        runtime.devTargetWeapon = MeleeWeaponProfile(damage: 10, reach: 1)
        _ = runtime.spawnDevTarget()

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

    // MARK: - Helpers

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
    private static func report(perStepMS: Double, hits: Int) throws {
        let text = """
        OpenSky combat loop budget (issue #374)

        actors:          \(crowdSize)
        steps:           \(budgetSteps)
        per-step:        \(String(format: "%.4f", perStepMS)) ms
        budget:          \(stepBudgetMS) ms
        blows landed:    \(hits)
        """
        // Through the shared helper rather than a relative path: the test host's
        // working directory is not the checkout, so `logs/...` resolves to the
        // filesystem root and the write fails.
        try PlayerBodyFixture.write(text, to: "combat-loop-budget.log")
    }
}

/// A world with a crowd standing around the player, for the budget measurement.
///
/// Deliberately not the app's own conformance: the number wanted here is the
/// loop's own cost — the state derivation and the attack clock — and running it
/// through a streamer would measure the streamer.
@MainActor
private final class CrowdedCombatWorld: CombatLoopWorld {
    let actors: [CombatActorObservation]
    private var hostility: [ReferenceKey: ActorHostility] = [:]

    init(count: Int) {
        actors = (0 ..< count).map { index in
            CombatActorObservation(
                key: .generated(UInt64(index + 1)),
                // A ring around the player, one of them inside reach so the
                // measurement includes the blow-landing path rather than only
                // the idle one.
                feet: SIMD3(60 + Float(index) * 40, 0, 0),
                name: "actor \(index)"
            )
        }
    }

    var combatPlayer: MeleeAttacker {
        MeleeAttacker(key: .player, feet: SIMD3<Float>(), facing: 0)
    }

    func combatActors() -> [CombatActorObservation] {
        actors
    }

    func combatHostility(of key: ReferenceKey) -> ActorHostility {
        hostility[key] ?? .neutral
    }

    @discardableResult
    func setCombatHostility(_ value: ActorHostility, on key: ReferenceKey) -> Bool {
        guard hostility[key] != value else { return false }
        hostility[key] = value
        return true
    }

    @discardableResult
    func applyCombatDamage(_ amount: Float, to key: ReferenceKey) -> Bool {
        amount > 0
    }

    func combatBlock(of key: ReferenceKey) -> MeleeBlockKind? {
        nil
    }

    @discardableResult
    func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        target == nil
    }

    func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {}

    @discardableResult
    func playCombatClip(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
        true
    }

    var combatTransients: CombatTransientCounts {
        .none
    }

    @discardableResult
    func trimCombatTransients(to limits: CombatTransientLimits) -> CombatTransientCounts {
        .none
    }

    func despawnCombatTransients() {}

    func setCombatMusicActive(_ active: Bool) {}
}
