// The M15 gate's fight, driven step by step (issue #198).
//
// One player and one opponent, driven by key and mouse events, over the
// synthetic arena in `M15AcceptanceFixture`. The whole path from a press to a
// landed hit is the shipping one:
//
//   NSEvent -> GameMetalView.keyDown/mouseDown -> CameraInputState -> CameraInput
//   -> LocomotionBridge.acceptFrame -> WalkController.update
//   -> LocomotionBridge.plan -> BehaviorGraphInstance.update (fires annotations)
//   -> LocomotionGraphEventQueue -> MeleeCombatRuntime / ArcheryRuntime /
//      RagdollRuntime -> ActorValueRuntime -> RagdollWorld -> CombatLoopRuntime
//
// Nothing here is a shortcut around a layer. The route enters at the top, at
// `GameMetalView`, which is the object the window hands an event to; what a
// headless test cannot drive is the `MTKView` draw callback above it, so the
// frame loop is spelled out here in the order `Renderer.advanceCamera` and the
// four `GameViewController` satellites spell it — melee on the drawn frame,
// then archery, ragdolls and the combat loop on the simulated delta, in the
// order `wireArchery`, `wireRagdoll` and `wireCombat` chain them. That is the
// same rule `M13AcceptanceChain` and `M14AcceptanceChain` followed.
//
// The clutter half runs against the real `CellStreamer` with the shared
// `ManualCellBuildRunner`, so a shoved crate is reconciled, stepped and settled
// by the engine's own registry rather than by a simulation of one.

import AppKit
import Foundation
@testable import opensky
import simd
import Testing

/// The gate's world. `init` only wires it; the route steps are separate calls
/// so a failure names the step rather than leaving an end state to explain.
@MainActor
final class M15AcceptanceChain {
    // MARK: - Identities and geometry

    /// US ANSI virtual key codes, the same physical layout `GameMetalView`
    /// maps. Spelled here rather than imported because the view keeps them
    /// private, which is right: they are its own input contract.
    enum Key: UInt16 {
        case keyW = 13
        case keyS = 1
        case keyR = 15
        case space = 49
    }

    static let player = ReferenceKey.player
    static let opponent = ReferenceKey.generated(1)
    static let crate = ReferenceKey.generated(2)
    static let opponentBase = FormID(0x0000_3000)
    static let opponentReference = FormID(0x0000_3100)
    static let coordinate = CellCoordinate(x: 0, y: 0)
    static let cell = CellSceneLocation.exterior(coordinate)
    /// The ammunition the player carries and a shot consumes.
    static let arrowItem = FormID(0x0001_397D)
    /// The bow the shot is taken with. A WEAP FormID rather than the unarmed
    /// profile, because "is a bow equipped" is answered by that field.
    static let bowItem = FormID(0x0001_397E)
    /// What the corpse is carrying, which loot has to move without losing.
    static let lootItem = FormID(0x0000_0200)
    static let lootCount: Int32 = 3

    /// Frame rate the route is driven at, matching `M14AcceptanceChain`.
    static let frameTime: Float = 1 / 60

    /// What both actors can hold, which is the one baseline the fallback
    /// resolver hands out; the opponent is then set below it so one swing and
    /// one arrow finish the fight rather than a montage.
    static let maximumHealth: Float = 100
    static let opponentHealth: Float = 40
    static let playerHealth: Float = 100
    /// The drawn weapon's damage and the bow's, chosen so the swing's
    /// arithmetic is exact and the arrow that follows it is fatal.
    static let weaponDamage: Float = 24
    static let arrowDamage: Float = 40
    static let bowDamage: Float = 6

    // MARK: - Wiring

    let view = GameMetalView(frame: CGRect(x: 0, y: 0, width: 64, height: 64), device: nil)
    let input = CameraInputState()
    let bridge: LocomotionBridge
    /// The player's graph, attached to the bridge, and the opponent's, stepped
    /// here. Two instances of one declaration set: an event raised on the
    /// opponent has to reach the opponent and nothing else, which is a claim
    /// only two graphs can carry.
    let graph: BehaviorGraphInstance
    let opponentGraph: BehaviorGraphInstance
    let streamer: CellStreamer
    let store = WorldStateStore()
    let actorValues: ActorValueRuntime
    let inventory: InventoryRuntime
    let melee: MeleeCombatRuntime
    let archery: ArcheryRuntime
    let ragdolls = RagdollRuntime()
    let combat: CombatLoopRuntime

    private(set) var camera: FreeFlyCamera
    private(set) var controller: WalkController
    private(set) var frames = 0

    /// Where the opponent is standing. Settable so the route can put it out of
    /// reach for the leg that shoots it.
    var opponentFeet = SIMD3<Float>(
        M15AcceptanceWorld.opponentX, M15AcceptanceWorld.startY, M15AcceptanceWorld.floorHeight
    )
    /// Death state the seam writes and reads back, mirrored into `store` so a
    /// save carries it.
    var deathStates: [ReferenceKey: ActorDeathState] = [:]
    /// Stuck arrows the projectile runtime asked the world to spawn.
    var stuckArrows: [(key: ReferenceKey, arrow: StuckProjectile)] = []
    /// Every state the player's graph entered, newest last, deduplicated.
    private(set) var visitedStates: [String] = []
    private(set) var opponentVisitedStates: [String] = []
    /// Events the opponent's graph fired, awaiting the ragdoll runtime.
    private var opponentFiredEvents: [String] = []
    var nextSpawnSequence: UInt64 = 100
    let runner = ManualCellBuildRunner()
    var completedBuilds = 0

    init() throws {
        graph = M15AcceptanceFixture.instance()
        opponentGraph = M15AcceptanceFixture.instance()
        bridge = LocomotionBridge(configuration: .synthetic)
        let start = SIMD3<Float>(
            M15AcceptanceWorld.startX,
            M15AcceptanceWorld.startY,
            M15AcceptanceWorld.floorHeight
        )
        camera = FreeFlyCamera(
            position: start + SIMD3<Float>(0, 0, PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: 0
        )
        controller = WalkController(cameraPosition: camera.position, configuration: .synthetic)
        streamer = CellStreamer(
            center: Self.coordinate, radius: 0, runner: runner
        ) { _, _ in }
        actorValues = ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineResolver(
                fallback: ActorValueBaseline(
                    maximums: ActorValues(
                        health: Self.maximumHealth, magicka: 50, stamina: 50
                    ),
                    regenPercentPerSecond: .zero
                )
            )
        )
        inventory = try InventoryRuntime(
            store: store, baselines: InventoryBaselineFixture.resolver()
        )
        melee = MeleeCombatRuntime(settings: .synthetic)
        archery = ArcheryRuntime(
            settings: .synthetic, projectiles: ProjectileRuntime(settings: .synthetic)
        )
        combat = CombatLoopRuntime(settings: .synthetic)
        view.input = input
        // The acceptance route clicks, and a click captures the pointer. The
        // capture's cursor side effects are swapped out so driving the gate
        // cannot freeze the machine's own cursor (issue #198).
        view.pointerCapture = .none
        try wire()
    }

    /// Attaches every runtime to this chain as its world, seeds the two
    /// inventories, and brings the start cell up the way the app does.
    private func wire() throws {
        bridge.attach(graph: graph)
        graph.activate()
        opponentGraph.activate()
        melee.attach(world: self)
        archery.attach(world: self)
        ragdolls.attach(seam: self)
        combat.attach(world: self)
        combat.devTargetWeapon = MeleeWeaponProfile(damage: 6, reach: 1)
        melee.weapon = MeleeWeaponProfile(
            damage: Self.weaponDamage, reach: 1, stagger: 0.5, handType: .sword
        )
        archery.bow = MeleeWeaponProfile(
            damage: Self.bowDamage, reach: 1, weapon: Self.bowItem, handType: .bow
        )
        archery.arrow = ArcheryAmmunition(
            item: Self.arrowItem,
            damage: Self.arrowDamage,
            profile: ProjectileProfile(speed: 3600, gravityFactor: 0.35, range: 60000)
        )
        // A body that comes to rest writes its resting pose into the world
        // state, which is what makes settled clutter survive a save. Wired the
        // way `GameViewControllerStreaming` wires it.
        streamer.onBodySettled = { [store] key, transform, placingCell in
            store.set(transform, for: key, in: placingCell)
        }
        try inventory.add(Self.arrowItem, count: 10, to: .player)
        try inventory.add(Self.lootItem, count: Self.lootCount, to: corpseHolder)
        // Both actors start at a number the assertions can quote back: the
        // player full, and the opponent low enough that the route's one swing
        // and one arrow are the whole fight.
        actorValues.set(.health, to: Self.playerHealth, on: .player)
        actorValues.set(.health, to: Self.opponentHealth, on: opponentHolder)
        streamer.update(cameraPosition: controller.cameraPosition)
        completePendingBuilds()
    }

    // MARK: - Reading the run

    var feetPosition: SIMD3<Float> {
        controller.feetPosition
    }

    /// The state the player's graph is showing, or nil before the first update.
    var currentState: String? {
        graph.activeStates.last?.stateName
    }

    var opponentState: String? {
        opponentGraph.activeStates.last?.stateName
    }

    var opponentHolder: ActorValueHolder {
        ActorValueHolder(
            key: Self.opponent,
            subject: .actor(base: Self.opponentBase),
            cell: Self.cell
        )
    }

    var corpseHolder: InventoryHolder {
        InventoryHolder(key: Self.opponent, owner: .generated, cell: Self.cell)
    }

    var opponentHealth: Float {
        actorValues.current(of: opponentHolder).health
    }

    var playerHealth: Float {
        actorValues.current(of: .player).health
    }

    var crateBody: DynamicBody? {
        streamer.dynamicBodies.body(for: Self.crate)
    }

    // MARK: - Frames

    /// One rendered frame, in the order the app runs it.
    func frame(dt: Float = M15AcceptanceChain.frameTime) {
        let frameInput = input.makeInput(dt: dt)
        bridge.acceptFrame(frameInput)
        controller.update(
            camera: &camera,
            input: frameInput,
            sampleGround: M15AcceptanceWorld.sampleGround,
            plan: { [bridge] state in bridge.plan(state) }
        )
        stepOpponentGraph(dt: dt)
        advanceMelee()
        advanceArchery(dt: dt)
        advanceRagdolls(dt: dt)
        advancePhysics(dt: dt)
        combat.advance(by: dt)
        frames += 1
        recordStates()
    }

    /// Runs frames until `condition` holds or `limit` frames have passed.
    @discardableResult
    func run(frames limit: Int, until condition: () -> Bool = { false }) -> Bool {
        for _ in 0 ..< limit {
            if condition() {
                return true
            }
            frame()
        }
        return condition()
    }

    /// Runs until the player's graph is back in its start state, then two
    /// frames further.
    ///
    /// One update fires one transition — the rule `M14AcceptanceTests` already
    /// records for locomotion — so an event raised on the very frame another
    /// transition completes is dropped rather than queued. A combat route
    /// presses far more often than a locomotion one, so every step lets the
    /// previous clip hand back before it presses anything. This is the route
    /// being deterministic about a known engine rule, not a workaround for a
    /// defect.
    @discardableResult
    func settleGraph(limit: Int = 120) -> Bool {
        let reached = run(frames: limit) {
            self.currentState == M15AcceptanceFixture.State.idle.name
        }
        run(frames: 2)
        return reached
    }

    /// Melee, on the drawn frame, exactly as `advanceMelee(renderer:)` runs it.
    private func advanceMelee() {
        let events = bridge.graphEvents.drain(bridge.meleeEventConsumer)
        melee.acceptFrame(bridge.meleeIntent)
        combat.notePlayerHits(melee.handleGraphEvents(events).map(\.target))
    }

    /// Archery, on the simulated delta. Projectiles advance unconditionally,
    /// which is the ordering rule `GameViewControllerArchery` records.
    private func advanceArchery(dt: Float) {
        let events = bridge.graphEvents.drain(bridge.archeryEventConsumer)
        var intent = bridge.archeryIntent
        intent.hasBowEquipped = archery.bow.weapon != nil
        archery.acceptFrame(intent)
        archery.handleGraphEvents(events)
        let struck = archery.advanceProjectiles(by: dt).compactMap(\.target)
        if !struck.isEmpty {
            combat.notePlayerHits(struck)
        }
    }

    /// Death and ragdolls: zero-health actors die, the opponent's own drained
    /// events hand off, and the live bodies step.
    private func advanceRagdolls(dt: Float) {
        _ = bridge.graphEvents.drain(bridge.ragdollEventConsumer)
        if actorValues.hasZeroHealth(opponentHolder) {
            ragdolls.noteZeroHealth(of: Self.opponent, killer: Self.player)
        }
        let events = opponentFiredEvents
        opponentFiredEvents.removeAll()
        for key in ragdolls.pendingHandOffs.sorted() {
            ragdolls.handleGraphEvents(events, on: key)
        }
        ragdolls.blendDuration = bridge.ragdollBlendDuration
            ?? HKBRigidBodyRagdollControlsModifier.vanillaBlendDuration
        ragdolls.advance(by: dt)
    }

    /// The clutter, through the streamer's own reconcile-shove-step-settle
    /// pass, with the walking capsule as the shover.
    private func advancePhysics(dt: Float) {
        streamer.update(
            cameraPosition: controller.cameraPosition,
            playerCapsule: PlayerCapsuleState(
                capsule: controller.capsule, feetPosition: controller.feetPosition
            ),
            frameTime: dt
        )
        completePendingBuilds()
    }

    /// The opponent's graph runs on the same clock the player's does. A real
    /// session steps every actor's graph from the animation layer; this is that
    /// step, reduced to the one actor the route has.
    private func stepOpponentGraph(dt: Float) {
        guard dt > 0 else { return }
        opponentFiredEvents.append(
            contentsOf: opponentGraph.update(deltaTime: dt).firedEvents.compactMap(\.name)
        )
    }

    private func recordStates() {
        if let name = currentState, visitedStates.last != name {
            visitedStates.append(name)
        }
        if let name = opponentState, opponentVisitedStates.last != name {
            opponentVisitedStates.append(name)
        }
    }
}
