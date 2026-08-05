// The M14 gate's route, driven step by step (issue #191).
//
// One player, driven by key events, over the synthetic world in
// `M14AcceptanceFixture`. The whole path from a key press to a moved capsule is
// the shipping one:
//
//   NSEvent -> GameMetalView.keyDown -> CameraInputState -> CameraInput
//   -> LocomotionBridge.acceptFrame -> WalkController.update
//   -> LocomotionBridge.plan -> BehaviorGraphInstance.update
//
// Nothing here is a shortcut around a layer. The route enters at the top, at
// `GameMetalView`, which is the object the window hands a key press to; what a
// headless test cannot drive is the `MTKView` draw callback above it, so the
// frame loop is spelled out here in the same order `Renderer.advanceCamera`
// spells it. That is the same rule `M13AcceptanceChain` followed one milestone
// earlier.
//
// The streaming and door halves run against the real `CellStreamer` with the
// shared `ManualCellBuildRunner`, so a cell crossing and a door round trip are
// the engine's own and not a simulation of one.

import AppKit
@testable import opensky
import simd
import Testing

/// Cell locations the streamer attached, in order. A reference type because the
/// streamer's callback is set during `init`, before `self` is available to
/// capture.
@MainActor
final class M14LocationLog {
    private(set) var locations: [CellSceneLocation] = []

    func note(_ location: CellSceneLocation?) {
        guard let location, locations.last != location else { return }
        locations.append(location)
    }
}

/// The gate's world. `init` only wires it; the route steps are separate calls
/// so a failure names the step rather than leaving an end state to explain.
@MainActor
final class M14AcceptanceChain {
    // MARK: - Identities and geometry

    /// US ANSI virtual key codes, the same physical layout `GameMetalView`
    /// maps. Spelled here rather than imported because the view keeps them
    /// private, which is right: they are its own input contract.
    enum Key: UInt16 {
        case keyW = 13
        case keyC = 8
        case space = 49
        case keyF = 3
    }

    static let doorReference: UInt32 = 0x0000_0A01
    static let interiorDoorReference: UInt32 = 0x0000_0A02
    static let interiorCell = FormID(0x0000_138C)

    /// Frame rate the route is driven at. Two fixed steps per frame at the
    /// controller's 120 Hz, which is what a comfortably-rendering session sees.
    static let frameTime: Float = 1 / 60

    /// Where the route starts: flat ground in cell (0, 0), west of everything.
    static let startX: Float = 200
    /// Where the door stands, in the cell east of the start.
    static var doorPosition: SIMD3<Float> {
        SIMD3<Float>(4600, startY, M14AcceptanceWorld.plateauHeight)
    }

    /// Where the interior places the player.
    static var interiorPosition: SIMD3<Float> {
        SIMD3<Float>(9000, 9000, 0)
    }

    /// One line of Y for the whole route, in cell (0, 0)'s middle.
    static let startY = CellGridManager.cellCenter(of: CellCoordinate(x: 0, y: 0)).y

    // MARK: - Wiring

    let view = GameMetalView(frame: CGRect(x: 0, y: 0, width: 64, height: 64), device: nil)
    let input = CameraInputState()
    let bridge: LocomotionBridge
    let graph: BehaviorGraphInstance
    let firstPersonGraph: BehaviorGraphInstance
    let streamer: CellStreamer
    private let runner = ManualCellBuildRunner()
    private(set) var camera: FreeFlyCamera
    private(set) var controller: WalkController
    /// Every state the third-person graph entered, newest last, deduplicated
    /// against the immediately preceding one. This is the route's own record of
    /// which locomotion states it reached.
    private(set) var visitedStates: [String] = []
    private(set) var firstPersonVisitedStates: [String] = []
    /// Cell locations the streamer attached, in order, straight off its own
    /// `onCellAttached` callback rather than inferred from a position.
    let attachedLocations = M14LocationLog()
    private(set) var frames = 0

    init() {
        graph = M14AcceptanceFixture.instance()
        firstPersonGraph = M14AcceptanceFixture.instance()
        bridge = LocomotionBridge(
            configuration: .synthetic,
            sampleWater: M14AcceptanceWorld.sampleWater
        )
        let start = SIMD3<Float>(
            Self.startX, Self.startY, M14AcceptanceWorld.flatHeight
        )
        camera = FreeFlyCamera(
            position: start + SIMD3<Float>(0, 0, PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: 0
        )
        controller = WalkController(cameraPosition: camera.position, configuration: .synthetic)
        streamer = CellStreamer(
            center: CellCoordinate(x: 0, y: 0), radius: 0, runner: runner
        ) { _, _ in }
        view.input = input
        let log = attachedLocations
        streamer.onCellAttached = { scene, _ in log.note(scene.location) }
        // The start cell, brought up the way every later one is.
        streamer.update(cameraPosition: controller.cameraPosition)
        completePendingBuilds()
        settleAndAttachGraphs()
    }

    /// Attaches both graphs, in the order the app does it: the bridge is built
    /// with no graph, and `attach(graph:)` runs once the install's own
    /// `0_master.hkx` has loaded, which is always after the controller exists.
    private func settleAndAttachGraphs() {
        bridge.attach(graph: graph)
        bridge.attachFirstPerson(graph: firstPersonGraph)
        graph.activate()
        firstPersonGraph.activate()
    }

    // MARK: - Reading the run

    var feetPosition: SIMD3<Float> {
        controller.feetPosition
    }

    var status: LocomotionStatus {
        bridge.status
    }

    /// The state the third-person graph is showing, or nil before the first
    /// update.
    var currentState: String? {
        graph.activeStates.last?.stateName
    }

    var firstPersonState: String? {
        firstPersonGraph.activeStates.last?.stateName
    }

    // MARK: - Input, through the shipping path

    func press(_ key: Key) {
        route(key, down: true)
    }

    func release(_ key: Key) {
        route(key, down: false)
    }

    /// Sets the modifier flags the way `flagsChanged` delivers them: shift is
    /// run, option is sprint.
    func setModifiers(run: Bool, sprint: Bool) {
        var flags: NSEvent.ModifierFlags = []
        if run {
            flags.insert(.shift)
        }
        if sprint {
            flags.insert(.option)
        }
        guard let event = Self.event(type: .flagsChanged, key: .keyW, flags: flags) else {
            Issue.record("AppKit refused to build a flagsChanged event")
            return
        }
        view.flagsChanged(with: event)
    }

    private func route(_ key: Key, down: Bool) {
        guard let event = Self.event(type: down ? .keyDown : .keyUp, key: key, flags: []) else {
            Issue.record("AppKit refused to build a key event for \(key)")
            return
        }
        if down {
            view.keyDown(with: event)
        } else {
            view.keyUp(with: event)
        }
    }

    private static func event(
        type: NSEvent.EventType,
        key: Key,
        flags: NSEvent.ModifierFlags
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: key.rawValue
        )
    }

    // MARK: - Frames

    /// One rendered frame, in `Renderer.advanceCamera`'s order: drain the
    /// input, hand it to the bridge, step the controller with the bridge as its
    /// planner, then let the streamer see where the player ended up.
    func frame(dt: Float = M14AcceptanceChain.frameTime) {
        let frameInput = input.makeInput(dt: dt)
        bridge.acceptFrame(frameInput)
        controller.update(
            camera: &camera,
            input: frameInput,
            sampleGround: M14AcceptanceWorld.sampleGround,
            plan: { [bridge] state in bridge.plan(state) }
        )
        frames += 1
        recordStates()
        guard !streamer.isInterior else { return }
        streamer.update(cameraPosition: controller.cameraPosition)
        completePendingBuilds()
    }

    /// Runs frames until `condition` holds or `limit` frames have passed.
    /// Answers whether the condition was reached, so a step that never arrives
    /// fails on its own line rather than on a distance assertion later.
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

    /// Runs until the capsule has passed `x`, or the budget runs out.
    @discardableResult
    func run(toX x: Float, limit: Int = 4000) -> Bool {
        run(frames: limit) { [self] in controller.feetPosition.x >= x }
    }

    private func recordStates() {
        if let name = currentState, visitedStates.last != name {
            visitedStates.append(name)
        }
        if let name = firstPersonState, firstPersonVisitedStates.last != name {
            firstPersonVisitedStates.append(name)
        }
    }

    // MARK: - Streaming

    /// Completes every cell build the streamer asked for. The cell east of the
    /// start carries the door, which is what makes the route cross a streaming
    /// boundary before it reaches one.
    private func completePendingBuilds() {
        let pending = runner.enqueued.suffix(from: min(completedBuilds, runner.enqueued.count))
        for coordinate in pending {
            completedBuilds += 1
            runner.complete(coordinate, with: .success(Self.exteriorScene(
                coordinate,
                door: coordinate.x == 1 ? Self.door() : nil
            )))
        }
        guard !pending.isEmpty else { return }
        streamer.update(cameraPosition: controller.cameraPosition)
    }

    private var completedBuilds = 0

    // MARK: - The door

    /// Looks at the door and presses the use key, exactly as the render loop
    /// would: one frame publishes the target, the next activates it.
    func pressUseKey(toward target: SIMD3<Float>) {
        let origin = controller.cameraPosition
        let ray = InteractionRay(origin: origin, direction: target - origin)
        streamer.update(cameraPosition: origin, interactionRay: ray)
        streamer.update(cameraPosition: origin, interactionRay: ray, activate: true)
    }

    /// Completes the pending door transition and re-seats the player where the
    /// destination placed them, which is what `Renderer.reseedMovement` does
    /// after a scene swap.
    func completeDoorTransition(
        from source: UInt32,
        to destination: UInt32,
        at placement: SIMD3<Float>,
        interior: Bool
    ) {
        let scene = interior
            ? Self.interiorScene(door: Self.interiorDoor())
            : Self.exteriorScene(CellCoordinate(x: 1, y: 0), door: Self.door())
        runner.completeDoorTransition(from: FormID(source), with: .success(DoorTransition(
            sourceDoor: FormID(source),
            destinationDoor: FormID(destination),
            destinationPlacement: PlacedReference.Placement(
                position: placement, rotation: .zero
            ),
            scene: scene
        )))
        streamer.update(cameraPosition: controller.cameraPosition)
        reseat(at: placement)
    }

    /// The teleport half of a door transition, spelled the way the renderer
    /// spells it: the capsule moves, and the bridge forgets its edge state so
    /// the next step cannot raise a landing or a swim exit for a place the
    /// player is no longer in.
    private func reseat(at placement: SIMD3<Float>) {
        camera.position = placement + SIMD3<Float>(0, 0, controller.capsule.eyeHeight)
        controller.reset(cameraPosition: camera.position)
        bridge.reset()
    }

    // MARK: - Scenes

    private static func exteriorScene(
        _ coordinate: CellCoordinate,
        door: PlacedDoor?
    ) -> CellScene {
        scene(location: .exterior(coordinate), door: door)
    }

    private static func interiorScene(door: PlacedDoor) -> CellScene {
        scene(location: .interior(interiorCell), door: door)
    }

    private static func scene(location: CellSceneLocation, door: PlacedDoor?) -> CellScene {
        guard let door else {
            return CellStreamerTests.cellScene(location: location)
        }
        return CellStreamerTests.cellScene(
            location: location,
            doors: [door],
            interactions: [door.reference: CellStreamerTests.interaction(
                reference: door.reference.rawValue,
                position: door.position,
                action: .open,
                name: "Gate Door",
                actionLabel: "Open"
            )],
            staticCollision: CellStreamerTests.collision(
                reference: door.reference.rawValue, position: door.position
            )
        )
    }

    private static func door() -> PlacedDoor {
        CellStreamerTests.door(
            reference: doorReference,
            destination: interiorDoorReference,
            position: doorPosition
        )
    }

    private static func interiorDoor() -> PlacedDoor {
        CellStreamerTests.door(
            reference: interiorDoorReference,
            destination: doorReference,
            position: interiorPosition
        )
    }
}
