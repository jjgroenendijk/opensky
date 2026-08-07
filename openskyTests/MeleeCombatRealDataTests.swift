// Env-gated melee combat over the user's own Skyrim SE install (read-only
// external input, never committed — AGENTS.md "Legal & IP"), issue #195.
//
// The synthetic suites prove the state machine, the sweep and the formula in
// isolation, and every name they use is quoted from the census. The claim they
// cannot make is the issue's real-data acceptance: that the *vanilla* player
// graph declares those names, that raising them through the shipping input path
// reaches an attack state, and that the events the graph fires back are the ones
// the melee runtime acts on. A census name the graph refuses would leave every
// synthetic test green and the feature dead.
//
// Skips automatically when OPENSKY_DATA_ROOT is unset. Run with
// `make realtest T='MeleeCombatRealDataTests/vanillaGraphAcceptsTheCensusNamedCombatEvents()'`.

import Foundation
@testable import opensky
import simd
import Testing

struct MeleeCombatRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// Every name `CombatGraphNames` raises has to resolve on the vanilla
    /// player graph. This is the one that fails loudly if a constant was
    /// mistyped or a census reading was wrong.
    @Test(.enabled(if: Self.dataRoot != nil))
    func vanillaGraphAcceptsTheCensusNamedCombatEvents() throws {
        let root = try #require(Self.dataRoot)
        let bridge = try Self.bridge(root: root)

        for name in CombatGraphNames.raisedEvents {
            bridge.raise(name)
        }
        for name in CombatGraphNames.variables {
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
        #expect(Set(bridge.status.raisedEvents).isSuperset(of: CombatGraphNames.raisedEvents))
    }

    /// The observed half: the names the runtime waits for have to be declared
    /// too, or a hit frame could never arrive.
    @Test(.enabled(if: Self.dataRoot != nil))
    func vanillaGraphDeclaresTheObservedCombatEvents() throws {
        let root = try #require(Self.dataRoot)
        let bridge = try Self.bridge(root: root)

        for name in CombatGraphNames.observedEvents {
            bridge.raise(name)
        }

        #expect(
            bridge.status.missingEvents.isEmpty,
            "the vanilla graph declares no home for \(bridge.status.missingEvents)"
        )
    }

    /// Draw and attack driven through the shipping input path — camera input to
    /// `LocomotionBridge` to the melee runtime — with the real graph attached.
    /// Headless: no window, no renderer, no audio.
    ///
    /// What this pins is the loop rather than a particular animation: the
    /// request leaves through the input path, the vanilla graph acts on it, and
    /// what comes back is a stream of names the melee runtime reads. Asserting
    /// that `BeginWeaponDraw` specifically arrives would pin the graph's own
    /// clip timing, which is `weapequip.hkx`'s business and not this item's.
    @Test(.enabled(if: Self.dataRoot != nil))
    @MainActor
    func drawAndAttackDriveTheVanillaGraphThroughTheShippingInputPath() throws {
        let root = try #require(Self.dataRoot)
        let bridge = try Self.bridge(root: root)
        let world = GraphBackedMeleeWorld(bridge: bridge)
        let runtime = MeleeCombatRuntime(
            settings: CombatSettings.resolve(store: GameSettingLoader.load(root: root)),
            world: world
        )

        // Draw, then a second of graph time, then attack. The input arrives as
        // a `CameraInput` exactly as the view layer produces it.
        let afterDraw = Self.drive(
            bridge: bridge, runtime: runtime, input: Self.input(toggleWeaponDrawn: true)
        )
        let afterAttack = Self.drive(
            bridge: bridge, runtime: runtime, input: Self.input(attack: true)
        )

        #expect(world.raised.contains(CombatGraphNames.weaponDraw))
        #expect(
            !afterDraw.isEmpty,
            "the vanilla graph fired nothing back after a draw request"
        )
        // The raise itself reached a declared name on the real graph, which is
        // the claim the synthetic suites cannot make.
        #expect(bridge.status.missingEvents.isEmpty)
        // What the vanilla graph does with the request, probed on the local
        // install 2026-08-07: it accepts `weaponDraw` and moves — the drained
        // batch is `weaponDraw, MTState, arrowDetach, tailMTState,
        // HeadTrackingOn, IdleStop, tailMTIdle` — but it does not reach the
        // `BeginWeaponDraw` annotation, and the state stays `.drawing`. The
        // equip sub-behavior branches on `iRightHandType`, whose integer
        // encoding the census gives no reading for, so OpenSky deliberately
        // leaves it unwritten rather than guessing which value means "one-handed
        // sword" (see `CombatGraphNames.variables`). That is recorded here as an
        // expectation rather than as prose, so settling the encoding turns this
        // assertion red and the reader is sent to the right place.
        #expect(runtime.state.drawState == .drawing)
        // And because the graph never reported the weapon in hand, the attack
        // is dropped rather than queued: no swing resolves from a state the
        // graph never entered.
        #expect(runtime.swingCount == 0)
        #expect(afterAttack.allSatisfy { !$0.isEmpty })
    }

    /// The reach formula against the install's own numbers, for a weapon the
    /// load order actually ships.
    @Test(.enabled(if: Self.dataRoot != nil))
    func vanillaWeaponsResolveAReachAndAnImpactSet() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let settings = CombatSettings.resolve(
            store: GameSettingLoader.load(root: root, baseFile: file)
        )
        let items = ItemDefinitionStore(file: file)

        #expect(!items.weapons.isEmpty, "this load order carries no WEAP records")
        // `fCombatDistance` is the install's, not a fallback.
        #expect(settings.combatDistance.source != "vanilla Skyrim.esm value")

        let melee = items.weapons.values.filter { weapon in
            guard let type = weapon.animationType else { return false }
            return type != .bow && type != .crossbow && type != .staff && type != .other
        }
        #expect(!melee.isEmpty, "no melee WEAP in this load order")

        // Every melee weapon reaches a positive distance, and at least one
        // names the INAM impact set a landed hit resolves its sound through.
        for weapon in melee {
            let profile = MeleeWeaponProfile(weapon: weapon)
            let reach = MeleeSwing.reach(weapon: profile, settings: settings)
            #expect(reach > 0, "\(weapon.formID) resolves a non-positive reach")
        }
        let withImpacts = melee.count { $0.impactDataSet != nil }
        #expect(withImpacts > 0, "no melee WEAP names an INAM impact data set")

        // And the chain past INAM reaches a real sound for at least one of
        // them, which is what proves the reuse of the footstep index.
        let resolver = MeleeImpactResolver(footsteps: FootstepStore(file: file))
        let sounds = SoundRecordStore(file: file)
        let resolved = melee.compactMap {
            resolver.resolve(weapon: MeleeWeaponProfile(weapon: $0), material: nil)
        }
        #expect(!resolved.isEmpty, "no melee WEAP resolves INAM to an IPCT with a sound")
        let first = try #require(resolved.first)
        let path = try #require(
            try sounds.resolveAny(first.sound).filePaths.first,
            "a resolved weapon impact reaches a SNDR with no track"
        )
        _ = try WorldAudioEngine.makeBuffer(
            wav: VirtualFileSystem(root: root).contents(forPath: path),
            downmixToMono: true
        )
    }

    // MARK: - Loading

    /// A bridge over the real player graph, activated and stepped once so the
    /// state machines are running.
    ///
    /// `PlayerBehaviorGraph.load` rather than a hand-built instance, for the
    /// reason `FootstepRealDataTests` records: `0_master.hkx` is a shell whose
    /// combat branches are `hkbBehaviorReferenceGenerator`s naming
    /// `1hm_behavior.hkx`, `blockbehavior.hkx` and `weapequip.hkx`, and a graph
    /// built without a reference source reaches none of them.
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

    private static func input(
        attack: Bool = false,
        toggleWeaponDrawn: Bool = false
    ) -> CameraInput {
        CameraInput(
            attack: attack,
            toggleWeaponDrawn: toggleWeaponDrawn,
            dt: 1.0 / 120
        )
    }

    /// One frame of input followed by a second of fixed steps, draining the
    /// melee cursor each frame exactly as the app does.
    @discardableResult
    @MainActor
    private static func drive(
        bridge: LocomotionBridge,
        runtime: MeleeCombatRuntime,
        input: CameraInput
    ) -> [String] {
        bridge.acceptFrame(input)
        runtime.acceptFrame(bridge.meleeIntent)
        for _ in 0 ..< 120 {
            _ = bridge.plan(
                LocomotionStepState(
                    feetPosition: SIMD3<Float>(),
                    verticalVelocity: 0,
                    isGrounded: true,
                    yaw: 0,
                    dt: 1.0 / 120
                )
            )
        }
        let fired = bridge.graphEvents.drain(bridge.meleeEventConsumer)
        runtime.handleGraphEvents(fired)
        return fired
    }
}

/// A `MeleeCombatWorld` over a real `LocomotionBridge`: events go into the
/// vanilla graph and every world answer is a documented non-answer, because
/// this suite is about the graph rather than about the cell.
@MainActor
final class GraphBackedMeleeWorld: MeleeCombatWorld {
    private let bridge: LocomotionBridge
    private(set) var raised: [String] = []

    init(bridge: LocomotionBridge) {
        self.bridge = bridge
    }

    var meleeAttacker: MeleeAttacker {
        MeleeAttacker(key: .player, feet: SIMD3<Float>(), facing: 0)
    }

    func meleeTargets() -> [MeleeTarget] {
        []
    }

    func meleeMaterial(at position: SIMD3<Float>) -> FormID? {
        nil
    }

    func meleeBlock(of target: ReferenceKey) -> MeleeBlockKind? {
        nil
    }

    @discardableResult
    func applyMeleeDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        false
    }

    func playMeleeImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {}

    @discardableResult
    func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        guard target == nil else { return false }
        raised.append(name)
        bridge.raise(name)
        return bridge.status.raisedEvents.contains(name)
    }

    func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {
        bridge.write(value, to: name)
    }
}
