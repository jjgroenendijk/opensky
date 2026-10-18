// The shell of the `World > AI & Navigation` panel: one actor selection for
// every section, the crosshair pick, and the move, stop and reevaluate actions.
// The rules live in `AINavigationCore`. See docs/engine/coordinators.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyNavigation
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyWorldInterface
import simd

/// What the AI & Navigation coordinator reads from the session.
@MainActor
public protocol AINavigationWorld: AnyObject {
    /// False when no cell is streamed.
    var isStreaming: Bool { get }
    /// Nil without a renderer.
    var camera: AICameraPose? { get }
    /// The same actor list the fight uses, so both panels agree.
    func actorCandidates() -> [AIActorCandidate]
    /// The nearest collision the ray hits, over every collision candidate.
    func nearestCollisionHit(ray: InteractionRay) -> InteractionRayHit?
    /// The resident actor placed by `reference`, or nil when it is not an actor.
    func residentActor(for reference: FormID) -> ReferenceKey?
    func movementReadout(for actor: ReferenceKey) -> NPCMovementReadout?
    var activeMoverCount: Int { get }
    func moveActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> NPCMoveCommandResult
    /// False when the actor had no mover.
    func stopActor(_ actor: ReferenceKey) -> Bool
    func isHostile(_ actor: ReferenceKey) -> Bool
    func setHostile(_ hostile: Bool, actor: ReferenceKey)
    /// What the actor rides, such as a cart, or nil.
    func vehicleCarrier(of actor: ReferenceKey) -> ReferenceKey?
}

extension AINavigationWorld {
    public func vehicleCarrier(of _: ReferenceKey) -> ReferenceKey? {
        nil
    }
}

@MainActor
public final class AINavigationCoordinator: AINavigationControlProviding {
    public private(set) var lastAction = AINavigationActionOutcome.idle

    /// Nil follows the nearest resident actor. A chosen actor that stops being
    /// resident also falls back to the nearest one.
    private var chosenActor: ReferenceKey?
    /// Keyed by camera pose: six sections read the snapshot twice a second, so
    /// a still camera pays for one 4,096-unit raycast.
    private var pick: AICrosshairPick?
    private let packages: PackageCoordinator
    weak let world: (any AINavigationWorld)?

    public init(packages: PackageCoordinator, world: any AINavigationWorld) {
        self.world = world
        self.packages = packages
    }

    public var aiNavigationSnapshot: AINavigationSnapshot {
        guard let world, world.isStreaming else { return .unavailable }
        let actors = actorOptions()
        let selected = AINavigationCore.resolve(chosenActor, in: actors)
        var snapshot = AINavigationSnapshot(
            isAvailable: true,
            actors: actors,
            selectedActor: selected,
            selectedActorName: AINavigationCore.name(of: selected, in: actors),
            movement: selected.flatMap(world.movementReadout(for:)),
            moverCount: world.activeMoverCount,
            moverLimit: NPCMovementRuntime.maximumSimultaneousMovers,
            package: selected.flatMap(packages.readout(for:)),
            packagedActorCount: packages.registeredActors.count,
            crosshairPoint: crosshairHit()?.position,
            selectedActorIsHostile: selected.map(world.isHostile) ?? false,
            lastActionText: lastAction.text
        )
        let runner = selected.flatMap { packages.executions[$0]?.runner }
        snapshot.procedure = runner?.primary
        snapshot.runningProcedures = runner?.runningMachines ?? []
        snapshot.carrier = selected.flatMap(world.vehicleCarrier(of:))
        return snapshot
    }

    public var selectedAIActor: ReferenceKey? {
        get { AINavigationCore.resolve(chosenActor, in: actorOptions()) }
        set {
            chosenActor = newValue
            let actors = actorOptions()
            let name = AINavigationCore.name(
                of: AINavigationCore.resolve(chosenActor, in: actors), in: actors
            )
            lastAction = .selected(name)
        }
    }

    public var selectedAIActorIsHostile: Bool {
        get {
            guard let world, let key = selectedAIActor else { return false }
            return world.isHostile(key)
        }
        set {
            let actors = actorOptions()
            guard let world, let key = AINavigationCore.resolve(chosenActor, in: actors) else {
                lastAction = .noActor(verb: "set hostility")
                return
            }
            world.setHostile(newValue, actor: key)
            lastAction = .regardSet(
                actor: AINavigationCore.name(of: key, in: actors), hostile: newValue
            )
        }
    }

    public func selectAIActorFromCrosshair() {
        guard let world, world.isStreaming, let reference = crosshairHit()?.reference else {
            lastAction = .crosshairEmpty(verb: "select")
            return
        }
        guard let key = world.residentActor(for: reference) else {
            lastAction = .notAnActor(reference)
            return
        }
        selectedAIActor = key
    }

    public func moveSelectedAIActorToCrosshair() {
        let actors = actorOptions()
        guard
            let world, world.isStreaming,
            let key = AINavigationCore.resolve(chosenActor, in: actors)
        else {
            lastAction = .noActor(verb: "move")
            return
        }
        guard let point = crosshairHit()?.position else {
            lastAction = .crosshairEmpty(verb: "move")
            return
        }
        lastAction = .moved(
            world.moveActor(key, to: point),
            actor: AINavigationCore.name(of: key, in: actors)
        )
    }

    public func stopSelectedAIActor() {
        let actors = actorOptions()
        guard
            let world, world.isStreaming,
            let key = AINavigationCore.resolve(chosenActor, in: actors)
        else {
            lastAction = .noActor(verb: "stop")
            return
        }
        let name = AINavigationCore.name(of: key, in: actors)
        lastAction = .stopped(actor: name, hadMover: world.stopActor(key))
    }

    public func reevaluateSelectedAIActorPackage() {
        let actors = actorOptions()
        guard let key = AINavigationCore.resolve(chosenActor, in: actors) else {
            lastAction = .noActor(verb: "reevaluate")
            return
        }
        let name = AINavigationCore.name(of: key, in: actors)
        guard packages.registeredActors[key] != nil else {
            lastAction = .noPackageStack(actor: name)
            return
        }
        packages.restart(key)
        let readout = packages.readout(for: key) ?? AINavigationCore.emptyPackageReadout(key)
        lastAction = .reevaluated(actor: name, readout)
    }

    private func actorOptions() -> [AIActorOption] {
        guard let world, let camera = world.camera else { return [] }
        return AINavigationCore.options(world.actorCandidates(), eye: camera.position)
    }

    private func crosshairHit() -> InteractionRayHit? {
        guard
            let world,
            let camera = world.camera,
            let ray = InteractionRay(
                origin: camera.position,
                direction: camera.forward,
                maximumDistance: AINavigationCore.pickDistance
            )
        else { return nil }
        if let pick, pick.origin == ray.origin, pick.direction == ray.direction {
            return pick.hit
        }
        let hit = world.nearestCollisionHit(ray: ray)
        pick = AICrosshairPick(origin: ray.origin, direction: ray.direction, hit: hit)
        return hit
    }
}

/// One crosshair raycast and the camera pose it was taken from.
private struct AICrosshairPick {
    let origin: SIMD3<Float>
    let direction: SIMD3<Float>
    let hit: InteractionRayHit?
}
