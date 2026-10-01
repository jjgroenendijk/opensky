// Combat acceptance on the real install: the synthetic fight over the vanilla
// player behavior graph. Every combat, archery, and ragdoll census name is
// declared, a draw and a swing reach a real contact frame, and the evaluator's
// tally is pinned. It needs no GPU; `M15AcceptanceRenderTests` holds the pixel
// half. The report in `logs/` holds class names and counts only.

import Foundation
@testable import OpenSkyActorsInterface
@testable import OpenSkyBehavior
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyConditions
@testable import OpenSkyFormatsMesh
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyWorld
import simd
import Testing

struct M15AcceptanceRealDataTests {
    /// The two `0_master.hkx` modifiers item 15.6 had to implement rather than
    /// count. Both were pass-throughs over the whole M14 route, 684 evaluations
    /// each, and the M14 close-out named them as M15's to close.
    private static let ragdollModifiers = [
        "hkbRigidBodyRagdollControlsModifier",
        "hkbKeyframeBonesModifier"
    ]

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    @MainActor
    func drivesTheWholeFightThroughTheVanillaPlayerGraph() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
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

    /// How often the fight evaluated each of the two combat modifiers, and how
    /// often each was still a pass-through. Reported, not asserted: a route may
    /// never reach a ragdoll modifier.
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

    /// Condition and Papyrus native registry sizes. The full sweeps are
    /// `ConditionRealDataTests` and `PexRealDataTests`; this does not repeat them.
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
        let directory = try RepositoryLogs.directory()
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
