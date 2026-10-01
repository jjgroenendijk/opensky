// The shell of the `World > AI & Navigation` panel: one actor selection for
// every section, the crosshair pick, and the move, stop and reevaluate actions.
// The rules live in `AINavigationCore`. See docs/engine/coordinators.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyPhysics
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
    func collisionCandidates(overlapping bounds: ModelBounds) -> [StaticCollisionShape]
    /// The resident actor placed by `reference`, or nil when it is not an actor.
    func residentActor(for reference: FormID) -> ReferenceKey?
    func movementReadout(for actor: ReferenceKey) -> NPCMovementReadout?
    var activeMoverCount: Int { get }
    func moveActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> NPCMoveCommandResult
    /// False when the actor had no mover.
    func stopActor(_ actor: ReferenceKey) -> Bool
    func isHostile(_ actor: ReferenceKey) -> Bool
    func setHostile(_ hostile: Bool, actor: ReferenceKey)
}

@MainActor
public final class AINavigationCoordinator: AINavigationControlProviding {
    public private(set) var lastActionText = "Select an actor, then move it, or watch its schedule."

    /// Nil follows the nearest resident actor. A chosen actor that stops being
    /// resident also falls back to the nearest one.
    private var chosenActor: ReferenceKey?
    /// Keyed by camera pose: six sections read the snapshot twice a second, so
    /// a still camera pays for one 4,096-unit raycast.
    private var pick: AICrosshairPick?
    private let packages: PackageCoordinator
    weak var world: (any AINavigationWorld)?

    public init(packages: PackageCoordinator) {
        self.packages = packages
    }

    public func attach(world: any AINavigationWorld) {
        self.world = world
    }

    public var aiNavigationSnapshot: AINavigationSnapshot {
        guard let world, world.isStreaming else { return .unavailable }
        let actors = actorOptions()
        let selected = AINavigationCore.resolve(chosenActor, in: actors)
        return AINavigationSnapshot(
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
            lastActionText: lastActionText
        )
    }

    public var selectedAIActor: ReferenceKey? {
        get { AINavigationCore.resolve(chosenActor, in: actorOptions()) }
        set {
            chosenActor = newValue
            let actors = actorOptions()
            let name = AINavigationCore.name(
                of: AINavigationCore.resolve(chosenActor, in: actors), in: actors
            )
            lastActionText = "Selected \(name)."
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
                lastActionText = "Cannot set hostility: no resident actor."
                return
            }
            world.setHostile(newValue, actor: key)
            let regard = newValue ? "hostile" : "neutral"
            lastActionText = "\(AINavigationCore.name(of: key, in: actors)) is now \(regard)."
        }
    }

    public func selectAIActorFromCrosshair() {
        guard let world, world.isStreaming, let reference = crosshairHit()?.reference else {
            lastActionText = "Cannot select: the crosshair is not on anything."
            return
        }
        guard let key = world.residentActor(for: reference) else {
            lastActionText = "Cannot select: \(reference) under the crosshair is not an actor."
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
            lastActionText = "Cannot move: no resident actor to act on."
            return
        }
        guard let point = crosshairHit()?.position else {
            lastActionText = "Cannot move: the crosshair is not on anything."
            return
        }
        lastActionText = AINavigationReadout.moveResultText(
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
            lastActionText = "Cannot stop: no resident actor to act on."
            return
        }
        let name = AINavigationCore.name(of: key, in: actors)
        lastActionText = world.stopActor(key)
            ? "Stopped \(name) where it stands."
            : "\(name) had no mover to stop."
    }

    public func reevaluateSelectedAIActorPackage() {
        let actors = actorOptions()
        guard let key = AINavigationCore.resolve(chosenActor, in: actors) else {
            lastActionText = "Cannot reevaluate: no resident actor to act on."
            return
        }
        let name = AINavigationCore.name(of: key, in: actors)
        guard packages.registeredActors[key] != nil else {
            lastActionText = "\(name) has no package stack registered."
            return
        }
        packages.resume(key)
        let readout = packages.readout(for: key) ?? AINavigationCore.emptyPackageReadout(key)
        lastActionText = "Reevaluated \(name): " + AIPackageReadout.selectionText(for: readout)
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
        let shapes = world.collisionCandidates(overlapping: ray.bounds)
        let hit = InteractionRaycaster.nearestHit(ray: ray, shapes: shapes)
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
