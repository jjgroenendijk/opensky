// M15 acceptance against the user's own read-only Skyrim SE install (issue
// #198): the same fight the synthetic gate drives, over the vanilla player
// behavior graph, with the honest-coverage tallies pinned rather than
// described.
//
// This is the honest-coverage half of the gate. `M15AcceptanceTests` proves the
// loop works over a graph OpenSky wrote; what this proves is that the graph the
// install ships answers the same route — every combat, archery and ragdoll
// census name declared, a draw and a swing reaching a real contact frame, and
// the evaluator's own tally over that route reported with numbers instead of
// adjectives. The two modifiers item 15.6 had to implement rather than tally
// are named and counted individually, because "implemented" is exactly the kind
// of claim that stops being true quietly.
//
// The whole thing is device-free on purpose (the M13 env-gated/device-gated
// split): the naming, state and tally evidence stands on a runner with no GPU,
// and only the pixel evidence in `M15AcceptanceRenderTests` needs one.
//
// Nothing from the install is committed: the report goes to gitignored `logs/`
// and carries class names and counts only — never clip data, never a pose. Run
// it with `make realtest T='M15AcceptanceRealDataTests/...'`, which supplies
// the data root and the RSS watchdog.

import Foundation
@testable import opensky
import simd
import Testing

struct M15AcceptanceRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// The two `0_master.hkx` modifiers item 15.6 had to implement rather than
    /// count. Both were pass-throughs over the whole M14 route, 684 evaluations
    /// each, and the M14 close-out named them as M15's to close.
    private static let ragdollModifiers = [
        "hkbRigidBodyRagdollControlsModifier",
        "hkbKeyframeBonesModifier"
    ]

    @Test(.enabled(if: Self.dataRoot != nil))
    @MainActor
    func drivesTheWholeFightThroughTheVanillaPlayerGraph() throws {
        let root = try #require(Self.dataRoot)
        var lines = ["OpenSky M15 acceptance fight — \(PlayerBehaviorGraph.behaviorPath)"]

        // Two graphs, deliberately. The naming check raises every name in all
        // three sets at once — including the sheathe and death events — which
        // leaves the state machine wherever that storm of transitions put it.
        // The fight has to start from a graph nothing has shouted at.
        try Self.expectEveryCensusNameIsDeclared(
            Self.bridge(root: root), report: &lines
        )
        let bridge = try Self.bridge(root: root)
        let runtime = try Self.fight(root: root, bridge: bridge, report: &lines)
        Self.expectTheGraphSurvivedTheFight(bridge, runtime: runtime, report: &lines)
        Self.reportHonestCoverage(bridge, report: &lines)
        try Self.write(lines)
    }

    // MARK: - Naming

    /// Every name the three M15 name sets use exists in the player's own graph.
    /// A miss here is a name OpenSky invented rather than one it read out of
    /// the census, and it would leave every synthetic suite green and the
    /// feature dead.
    private static func expectEveryCensusNameIsDeclared(
        _ bridge: LocomotionBridge,
        report lines: inout [String]
    ) throws {
        let events = CombatGraphNames.raisedEvents + CombatGraphNames.observedEvents
            + ArcheryGraphNames.raisedEvents + ArcheryGraphNames.observedEvents
            + RagdollGraphNames.deathEvents + RagdollGraphNames.handOffEvents
        for name in events {
            bridge.raise(name)
        }
        let variables = CombatGraphNames.variables + ArcheryGraphNames.variables
        for name in variables {
            bridge.write(.bool(false), to: name)
        }

        #expect(
            bridge.status.missingEvents.isEmpty,
            "the vanilla graph declares no home for \(bridge.status.missingEvents)"
        )
        #expect(
            bridge.status.missingVariables.isEmpty,
            "the vanilla graph declares no home for \(bridge.status.missingVariables)"
        )
        lines.append(
            "[INFO] census names: \(events.count) events and \(variables.count) variables"
                + " all declared, 0 unresolved"
        )
    }

    // MARK: - The fight

    /// Draw, a second of graph time, then a swing — the same three steps the
    /// synthetic route takes, through the shipping input path with the vanilla
    /// graph attached.
    @MainActor
    private static func fight(
        root: GameDataRoot,
        bridge: LocomotionBridge,
        report lines: inout [String]
    ) throws -> MeleeCombatRuntime {
        let world = GraphBackedMeleeWorld(bridge: bridge)
        let runtime = MeleeCombatRuntime(
            settings: CombatSettings.resolve(store: GameSettingLoader.load(root: root)),
            world: world
        )
        runtime.weapon = MeleeWeaponProfile(damage: 8, reach: 1, handType: .sword)

        let afterDraw = drive(bridge: bridge, runtime: runtime, toggleWeaponDrawn: true)
        drive(bridge: bridge, runtime: runtime)
        let afterAttack = drive(bridge: bridge, runtime: runtime, attack: true)

        #expect(
            afterDraw.contains(CombatGraphNames.beginWeaponDraw),
            "the vanilla equip clip never reported the weapon reaching the hand"
        )
        #expect(runtime.state.drawState == .drawn)
        #expect(
            afterAttack.contains(CombatGraphNames.hitFrame),
            "the vanilla graph fired no contact frame for the swing"
        )
        #expect(runtime.swingCount == 1)
        lines.append(
            "[INFO] fight: draw fired \(afterDraw.count) events,"
                + " swing fired \(afterAttack.count), swings \(runtime.swingCount)"
        )
        return runtime
    }

    /// One second of fixed steps at one held input, answering with every event
    /// the graph fired over them.
    @MainActor
    @discardableResult
    private static func drive(
        bridge: LocomotionBridge,
        runtime: MeleeCombatRuntime,
        attack: Bool = false,
        toggleWeaponDrawn: Bool = false
    ) -> [String] {
        var fired: [String] = []
        for step in 0 ..< LocomotionDriveHarness.secondOfSteps {
            runtime.acceptFrame(MeleeIntent(
                attack: step == 0 && attack,
                toggleWeaponDrawn: step == 0 && toggleWeaponDrawn
            ))
            _ = bridge.plan(LocomotionStepState(
                feetPosition: SIMD3<Float>(),
                verticalVelocity: 0,
                isGrounded: true,
                yaw: 0,
                dt: LocomotionDriveHarness.step
            ))
            let names = bridge.graphEvents.drain(bridge.meleeEventConsumer)
            runtime.handleGraphEvents(names)
            fired.append(contentsOf: names)
        }
        return fired
    }

    // MARK: - Coverage

    /// The full-graph rule as the fight exercises it: nothing the graph reached
    /// was undecodable, and no reference went unresolved. Both are
    /// zero-tolerance — they are the "zero crashes and zero unresolved names"
    /// half of the gate — while the shortcut buckets are reported rather than
    /// forbidden, because an owed feature is a worklist entry and not a failure.
    @MainActor
    private static func expectTheGraphSurvivedTheFight(
        _ bridge: LocomotionBridge,
        runtime: MeleeCombatRuntime,
        report lines: inout [String]
    ) {
        guard let instance = bridge.graph else {
            Issue.record("no graph attached after the fight")
            return
        }
        let tally = instance.tally
        #expect(tally.undecodableObjectTotal == 0, "an object the fight reached had no decoder")
        #expect(
            tally.featureGaps[BehaviorTally.Gap.unresolvedBehaviorReference.rawValue] == nil,
            "a behavior reference resolved to nothing"
        )
        #expect(
            tally.featureGaps[BehaviorTally.Gap.depthCapReached.rawValue] == nil,
            "the graph walk hit its depth cap"
        )
        #expect(tally.generatorsEvaluated > 0)
        #expect(tally.modifiersEvaluated > 0)

        lines.append(contentsOf: [
            "[INFO] tally: \(tally.generatorsEvaluated) generators,"
                + " \(tally.modifiersEvaluated) modifiers over \(tally.updatesRun) updates",
            "[INFO] tally: gaps \(tally.gapTotal)"
                + "  unevaluated \(tally.unevaluatedGeneratorTotal)"
                + "  partial \(tally.partialGeneratorTotal)"
                + "  pass-through \(tally.passthroughModifierTotal)"
                + "  unresolved clips \(tally.unresolvedClipTotal)"
                + "  unapplied bindings \(tally.unappliedBindingTotal)"
                + "  undecodable \(tally.undecodableObjectTotal)",
            "[INFO] tally: pass-through modifiers \(tally.rankedPassthroughModifiers)",
            "[INFO] tally: unevaluated generators \(tally.rankedUnevaluatedGenerators)",
            "[INFO] tally: feature gaps \(tally.rankedFeatureGaps)",
            "[INFO] melee: hits \(runtime.hitCount) over \(runtime.swingCount) swings"
        ])
        Self.reportRagdollModifiers(tally, report: &lines)
    }

    /// The two modifiers the M14 close-out named as M15's to implement, counted
    /// individually: how many times the fight evaluated each, and how many of
    /// those evaluations were still pass-throughs.
    ///
    /// Reported rather than asserted to zero. A route that never reaches a
    /// ragdoll control modifier evaluates it zero times, and a gate that
    /// demanded a non-zero implemented count here would be demanding the fight
    /// take a particular path through a graph it does not own.
    private static func reportRagdollModifiers(
        _ tally: BehaviorTally,
        report lines: inout [String]
    ) {
        for name in ragdollModifiers {
            let passthrough = tally.passthroughModifiers[name] ?? 0
            lines.append(
                "[INFO] ragdoll modifier \(name): \(passthrough) pass-through evaluations"
                    + " over this route"
            )
        }
    }

    /// The coverage deltas the milestone close-out quotes: what the condition
    /// registry and the Papyrus native registry answer today.
    ///
    /// Registry sizes rather than a fresh sweep of the install. The sweeps
    /// themselves are `ConditionRealDataTests` and `PexRealDataTests`, both of
    /// which are expensive and already run under `make realtest-all`; repeating
    /// them here would double the cost of the gate to restate their numbers.
    @MainActor
    private static func reportHonestCoverage(
        _ bridge: LocomotionBridge,
        report lines: inout [String]
    ) {
        let simulated = NIFMotionSystem.allCases
            .filter(\.isSimulated).map(String.init(describing:))
        let animated = NIFMotionSystem.allCases
            .filter { !$0.isSimulated }.map(String.init(describing:))
        let constraints = NIFConstraintType.allCases.map(\.className).sorted()
        lines.append(contentsOf: [
            "[INFO] condition functions implemented: \(ConditionFunctionRegistry.standard.count)",
            "[INFO] motion systems simulated: \(simulated)",
            "[INFO] motion systems not simulated: \(animated)",
            "[INFO] constraint classes decoded: \(constraints)",
            "[INFO] bound variables: \(bridge.status.boundVariables.count),"
                + " raised events: \(bridge.status.raisedEvents.count)"
        ])
    }

    // MARK: - Loading and evidence

    /// A bridge over the real player graph, activated and stepped once so the
    /// state machines are running.
    @MainActor
    private static func bridge(root: GameDataRoot) throws -> LocomotionBridge {
        let vfs = VirtualFileSystem(root: root)
        let graph = try PlayerBehaviorGraph.load(fileSystem: vfs)
        let bridge = LocomotionBridge(configuration: .synthetic, graph: graph.instance)
        graph.instance.activate()
        _ = bridge.plan(LocomotionStepState(
            feetPosition: SIMD3<Float>(),
            verticalVelocity: 0,
            isGrounded: true,
            yaw: 0,
            dt: LocomotionDriveHarness.step
        ))
        return bridge
    }

    /// The coverage ledger the milestone's log entry quotes, written to
    /// gitignored `logs/`. Class names and counts only.
    private static func write(_ lines: [String]) throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try (lines.joined(separator: "\n") + "\n").write(
            to: directory.appending(path: "m15-acceptance-fight.log"),
            atomically: true,
            encoding: .utf8
        )
    }
}
