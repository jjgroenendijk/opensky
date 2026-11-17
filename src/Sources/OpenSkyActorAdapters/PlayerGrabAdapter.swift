// The player's grab in the running world: Activate held on a loose object or a dead body
// holds it on a spring ahead of the camera (docs/engine/grab.md).

public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `PlayerGrabAdapter` reads from the session.
@MainActor
public protocol PlayerGrabHost: AnyObject, SendableMetatype {
    var gameSession: (any GameSessionPort)? { get }
    /// The carry weight of an item's base form; nil for a form that is not an item.
    func itemWeight(of base: FormID) -> Float?
    var ragdoll: any RagdollPort { get }
    var streamer: any CellStreamerPort { get }
}

/// The object under the crosshair when Activate went down, and its plain activation.
struct GrabCandidate {
    let key: ReferenceKey
    let point: SIMD3<Float>
    let target: InteractionTarget?
}

/// What is held now.
struct PlayerGrabHeld {
    let key: ReferenceKey
    let reference: FormID
    /// The ragdoll body held by, for an actor.
    let body: Int?
    let mass: Float
    let hold: GrabHold
}

public final class PlayerGrabAdapter: PlayerGrabPort {
    public let game: any PlayerGrabHost
    public let settings: GrabSettings
    /// The launcher setting; off, Activate never grabs.
    public var isEnabled: Bool
    private var useKey: GrabUseKey
    private var held: PlayerGrabHeld?
    private var pressed: GrabCandidate?
    private var lastLetGo: String?
    /// A hold the agent command started: no Activate key keeps it, so a key that is up
    /// does not end it.
    private var isHeldByCommand = false

    /// Without a stage, as in a test, it registers nothing.
    public init(
        game: any PlayerGrabHost, stage: SessionStage?, settings: GrabSettings,
        isEnabled: Bool = true
    ) {
        self.game = game
        self.settings = settings
        self.isEnabled = isEnabled
        useKey = GrabUseKey(holdDelay: settings.holdDelay)
        stage?.gameSession.worldTick.register(.grab) { [weak self] delta in
            self?.steer(delta: delta)
        }
    }

    public var grabReadout: PlayerGrabReadout {
        let phase = switch useKey.phase {
        case .idle: "idle"
        case .waiting: "waiting"
        case .holding: "holding"
        }
        return PlayerGrabReadout(
            isEnabled: isEnabled, phase: phase, held: held?.reference.rawValue,
            body: held?.body, distance: held?.hold.distance, strength: held?.hold.strength,
            lastLetGo: lastLetGo
        )
    }

    // MARK: - The Activate key

    /// A press while holding is the one that lets go; a press on a grabbable object waits
    /// to see whether it is a tap or a hold. True when the press was taken.
    public func takeActivation() -> Bool {
        guard isEnabled else { return false }
        if isHeldByCommand {
            letGo(because: "released")
            return true
        }
        if useKey.isHolding {
            return useKey.press(onGrabbable: false)
        }
        guard
            let candidate = candidateUnderCrosshair(),
            useKey.press(onGrabbable: true) else { return false }
        pressed = candidate
        return true
    }

    /// Each frame with the key's state: a tap activates as a plain press would.
    public func advanceUseKey(by delta: Float, isDown: Bool) {
        guard !isHeldByCommand else { return }
        switch useKey.advance(by: delta, isDown: isDown) {
        case .tap:
            if let target = pressed?.target {
                game.streamer.residents.activate(target)
            }
            pressed = nil
        case .grab:
            if let pressed, start(pressed.key, at: pressed.point) {
                lastLetGo = nil
            } else {
                useKey.drop()
            }
            pressed = nil
        case .letGo:
            letGo(because: "released")
        case nil:
            break
        }
    }

    // MARK: - The port

    /// The command has no crosshair, so it turns the view to the object first, as a
    /// player aims before holding Activate.
    public func grab(_ key: ReferenceKey) -> Bool {
        guard isEnabled, held == nil, let point = position(of: key, body: nil) else {
            return false
        }
        face(point)
        guard start(key, at: point) else { return false }
        _ = useKey.press(onGrabbable: true)
        _ = useKey.advance(by: settings.holdDelay, isDown: true)
        isHeldByCommand = true
        lastLetGo = nil
        return true
    }

    public func letGo() {
        letGo(because: "released")
    }

    private func letGo(because reason: String) {
        guard held != nil || useKey.isHolding else { return }
        held = nil
        isHeldByCommand = false
        game.gameSession?.locomotion.isCarryingHeavyItem = false
        useKey.drop()
        lastLetGo = reason
    }

    // MARK: - Picking and starting

    private func start(_ key: ReferenceKey, at point: SIMD3<Float>) -> Bool {
        guard isGrabbable(key), let aim else { return false }
        let radius = game.gameSession?.walkController.capsule.radius
            ?? PlayerCapsule.standard.radius
        let distance = simd_distance(aim.eye, point)
        if let body = game.streamer.dynamicBodies.body(for: key) {
            let trap = body.definition.collisionLayer == Self.trapLayer
            held = PlayerGrabHeld(
                key: key, reference: body.reference, body: nil, mass: body.definition.mass,
                hold: GrabHold(
                    strength: .of(.object(trap: trap), settings: settings),
                    grabDistance: distance, playerRadius: radius, settings: settings
                )
            )
            game.gameSession?.locomotion.isCarryingHeavyItem =
                itemWeight(of: key) > settings.noRunItemWeight
            return true
        }
        guard
            let instance = game.ragdoll.runtime?.world.instance(for: key),
            let reference = game.streamer.referenceEntry(key: key)?.formID,
            let nearest = instance.bodies.indices.min(by: {
                simd_distance(instance.bodies[$0].position, point)
                    < simd_distance(instance.bodies[$1].position, point)
            })
        else { return false }
        let total = instance.bodies.reduce(0) { $0 + $1.definition.mass }
        held = PlayerGrabHeld(
            key: key, reference: reference, body: nearest,
            mass: instance.bodies[nearest].definition.mass,
            hold: GrabHold(
                strength: .of(.actor(totalMass: total, jointed: true), settings: settings),
                grabDistance: distance, playerRadius: radius, settings: settings
            )
        )
        return true
    }

    // MARK: - The spring

    /// Each world tick: pull the held body toward the point ahead of the camera, or let
    /// go when the hold breaks or the object is gone.
    func steer(delta: Float) {
        guard let held, delta > 0 else { return }
        guard let aim else {
            letGo(because: "no aim")
            return
        }
        let streamer = game.streamer
        let blocked = InteractionRay(
            origin: aim.eye, direction: aim.look, maximumDistance: held.hold.distance
        ).flatMap { streamer.collision.nearestCollisionHit(ray: $0) }
            .flatMap { $0.reference == held.reference ? nil : $0.distance }
        let target = held.hold.target(eye: aim.eye, look: aim.look, blocked: blocked)
        if let body = streamer.dynamicBodies.body(for: held.key) {
            guard !letsGo(held, target: target, at: body.position) else { return }
            let velocity = held.hold.velocity(
                position: body.position, velocity: body.linearVelocity, target: target, dt: delta
            )
            streamer.dynamicBodies.applyImpulse(
                (velocity - body.linearVelocity) * body.definition.mass,
                at: body.position, to: held.key
            )
            return
        }
        guard
            let index = held.body, let runtime = game.ragdoll.runtime,
            let bodies = runtime.world.instance(for: held.key)?.bodies,
            bodies.indices.contains(index)
        else {
            letGo(because: "gone")
            return
        }
        let body = bodies[index]
        guard !letsGo(held, target: target, at: body.position) else { return }
        let velocity = held.hold.velocity(
            position: body.position, velocity: body.linearVelocity, target: target, dt: delta
        )
        runtime.steerBody(index, of: held.key, velocity: velocity)
    }

    /// No contact query reaches the held body yet, so only the stretch breaks the hold.
    private func letsGo(_ held: PlayerGrabHeld, target: SIMD3<Float>, at point: SIMD3<Float>)
        -> Bool
    {
        guard held.hold.letsGo(
            target: target, held: point, objectMass: held.mass, heaviestContact: nil
        ) else { return false }
        letGo(because: "stretched")
        return true
    }
}

// MARK: - Picking

extension PlayerGrabAdapter {
    private func face(_ point: SIMD3<Float>) {
        guard let session = game.gameSession, session.movementMode.isPlayerControlled else {
            return
        }
        let look = point - session.freeFlyCamera.position
        let length = simd_length(look)
        guard length > 0, length.isFinite else { return }
        session.freeFlyCamera.yaw = atan2f(look.y, look.x)
        session.freeFlyCamera.pitch = min(
            max(asinf(look.z / length), -FreeFlyCamera.maxPitch), FreeFlyCamera.maxPitch
        )
    }

    private var aim: (eye: SIMD3<Float>, look: SIMD3<Float>)? {
        guard
            let session = game.gameSession,
            let ray = PlayerViewRay.make(
                mode: session.movementMode,
                camera: session.freeFlyCamera,
                feetPosition: session.walkController.feetPosition
            )
        else { return nil }
        return (ray.origin, ray.direction)
    }

    /// The activation target when it is grabbable, else the first collision hit.
    private func candidateUnderCrosshair() -> GrabCandidate? {
        let streamer = game.streamer
        if
            let target = streamer.interactionTarget,
            let key = streamer.referenceEntry(formID: target.interaction.reference)?.key,
            isGrabbable(key)
        {
            return GrabCandidate(key: key, point: target.hitPosition, target: target)
        }
        guard
            let aim,
            let ray = InteractionRay(origin: aim.eye, direction: aim.look),
            let hit = streamer.collision.nearestCollisionHit(ray: ray),
            let key = streamer.referenceEntry(formID: hit.reference)?.key,
            isGrabbable(key)
        else { return nil }
        return GrabCandidate(key: key, point: hit.position, target: nil)
    }

    /// A loose body light enough, or a dead actor's ragdoll whose root is light enough.
    private func isGrabbable(_ key: ReferenceKey) -> Bool {
        if let body = game.streamer.dynamicBodies.body(for: key) {
            return body.definition.mass <= settings.maximumMass
        }
        guard
            let runtime = game.ragdoll.runtime, runtime.isDead(key),
            let root = runtime.world.instance(for: key)?.bodies.first
        else { return false }
        return root.definition.mass <= settings.maximumMass
    }

    /// The carry weight of the held item's base form; a body or a static has none.
    private func itemWeight(of key: ReferenceKey) -> Float {
        guard let base = game.streamer.referenceEntry(key: key)?.placedReference?.base else {
            return 0
        }
        return game.itemWeight(of: base) ?? 0
    }

    /// Collision layer 14, TRAP: a trap's swinging log or blade is held more softly.
    static let trapLayer: UInt8 = 14

    private func position(of key: ReferenceKey, body: Int?) -> SIMD3<Float>? {
        if let loose = game.streamer.dynamicBodies.body(for: key) {
            return loose.position
        }
        guard let bodies = game.ragdoll.runtime?.world.instance(for: key)?.bodies else {
            return nil
        }
        return bodies.indices.contains(body ?? 0) ? bodies[body ?? 0].position : nil
    }
}
