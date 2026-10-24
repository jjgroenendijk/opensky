// Trap natives that change the world: `PlaceAtMe`, `ApplyHavokImpulse`,
// `PushActorAway`, and the pushback and stagger of `ProcessTrapHit`. The app answers
// through `PapyrusTrapWorldBridge`. See docs/engine/traps.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldState
import simd

/// What the trap natives reach in the running game. The app answers it.
@MainActor
public protocol PapyrusTrapWorldBridge: AnyObject {
    /// Places `count` copies of the base form `base` at `anchor`. Returns the last
    /// placed reference, or nil when the base cannot be placed here.
    func placeAtMe(_ base: ReferenceKey, at anchor: ReferenceKey, count: Int) -> ReferenceKey?
    /// Pushes a simulated body. False when `reference` has no dynamic body.
    func applyImpulse(_ impulse: SIMD3<Float>, to reference: ReferenceKey) -> Bool
    /// Knocks an actor back at `speed` units per second, along `direction` or, when
    /// it is nil, away from `source`. A negative speed pulls. False when the actor
    /// cannot be pushed.
    func pushActor(
        _ actor: ReferenceKey, awayFrom source: ReferenceKey,
        along direction: SIMD3<Float>?, speed: Float
    ) -> Bool
    /// Staggers an actor by `magnitude`, 0 to 1. False when it cannot stagger.
    func staggerActor(_ actor: ReferenceKey, magnitude: Float) -> Bool
    /// Sets whether a reference's collision simulates. False when it has no cell.
    func setMotionType(_ motionType: ReferenceMotionType, of reference: ReferenceKey) -> Bool
    /// Puts an object back where its plugin placed it, or at `target`. False for an actor.
    func resetReference(_ reference: ReferenceKey, to target: ReferenceKey?) -> Bool
    /// Fires `weapon` with `ammunition` from `source`, along its facing. False when
    /// nothing flies.
    func fireWeapon(
        _ weapon: ReferenceKey, from source: ReferenceKey, ammunition: ReferenceKey?
    ) -> Bool
}

/// The receiver of a trap-world native and the worlds it reaches.
@MainActor
struct TrapWorldTarget {
    let world: PapyrusWorldStateBridge
    let trapWorld: any PapyrusTrapWorldBridge
    let key: ReferenceKey
}

extension PapyrusNativeFunctions {
    /// `PushActorAway` force to speed, in units per second. [WARNING] Not confirmed.
    static let knockbackSpeedPerForce: Float = 100

    static func installTrapWorld(into registry: inout PapyrusNativeRegistry) {
        installPlaceAtMe(into: &registry)
        installPlaceActorAtMe(into: &registry)
        // The CK wiki: the vector is normalized first, and a zero-length one fails.
        trapWorldReference("ApplyHavokImpulse", into: &registry) { call, target in
            guard
                let direction = vector(call, from: 0), simd_length(direction) > 0,
                let magnitude = float(call, at: 3), magnitude.isFinite
            else {
                return failure(call, "ApplyHavokImpulse needs a direction and a magnitude")
            }
            _ = target.trapWorld.applyImpulse(
                simd_normalize(direction) * magnitude, to: target.key
            )
            return .returned(.none)
        }
        trapWorldReference("PushActorAway", into: &registry) { call, target in
            guard
                let handle = objectArgument(call, at: 0),
                let actor = target.world.referenceKey(for: handle),
                let force = float(call, at: 1), force.isFinite
            else { return failure(call, "PushActorAway needs an actor and a force") }
            // A negative force pulls the actor in (CK wiki "PushActorAway").
            _ = target.trapWorld.pushActor(
                actor, awayFrom: target.key, along: nil, speed: force * knockbackSpeedPerForce
            )
            return .returned(.none)
        }
    }

    /// `ObjectReference PlaceAtMe(Form akFormToPlace, int aiCount = 1, ...)`. A base
    /// the app cannot place answers None, as the game does for a failed placement.
    private static func installPlaceAtMe(into registry: inout PapyrusNativeRegistry) {
        trapWorldReference("PlaceAtMe", into: &registry) { call, target in
            guard
                let handle = objectArgument(call, at: 0),
                let base = target.world.referenceKey(for: handle)
            else { return failure(call, "PlaceAtMe needs a form to place") }
            let count = max(1, Int(integer(call, at: 1) ?? 1))
            guard
                let placed = target.trapWorld.placeAtMe(base, at: target.key, count: count),
                let result = target.world.objectHandle(for: placed)
            else { return .returned(.none) }
            return .returned(.object(result))
        }
    }

    /// `Actor PlaceActorAtMe(ActorBase akActorToPlace, int aiLevelMod = 4, EncounterZone
    /// akZone = None)`. The level modifier and zone are not read (docs/engine/traps.md).
    private static func installPlaceActorAtMe(into registry: inout PapyrusNativeRegistry) {
        scriptState("ObjectReference", "PlaceActorAtMe", into: &registry) { call, bridge, key in
            guard
                let handle = objectArgument(call, at: 0),
                let base = bridge.referenceKey(for: handle)
            else { return failure(call, "PlaceActorAtMe needs an actor base") }
            guard
                let placed = bridge.spawnReference(of: base, at: key),
                let result = bridge.objectHandle(for: placed)
            else { return .returned(.none) }
            return .returned(.object(result))
        }
    }

    /// The pushback and stagger of `ProcessTrapHit(akTrap, afDamage, afPushback, afXVel,
    /// afYVel, afZVel, afXPos, afYPos, afZPos, aeMaterial, afStagger)`: the trap's
    /// velocity gives the direction.
    static func pushBack(
        _ call: PapyrusNativeCall, world: any PapyrusWorldBridge, actor: ReferenceKey
    ) {
        guard let trapWorld = (world as? PapyrusWorldStateBridge)?.trapWorld else { return }
        if let stagger = float(call, at: 10), stagger.isFinite, stagger > 0 {
            _ = trapWorld.staggerActor(actor, magnitude: min(stagger, 1))
        }
        guard
            let pushback = float(call, at: 2), pushback.isFinite, pushback > 0,
            let handle = objectArgument(call, at: 0),
            let trap = world.referenceKey(for: handle)
        else { return }
        let velocity = vector(call, from: 3)
        let direction = velocity.flatMap { simd_length($0) > 0 ? simd_normalize($0) : nil }
        _ = trapWorld.pushActor(actor, awayFrom: trap, along: direction, speed: pushback)
    }

    static func vector(_ call: PapyrusNativeCall, from index: Int) -> SIMD3<Float>? {
        guard
            let x = float(call, at: index), let y = float(call, at: index + 1),
            let z = float(call, at: index + 2)
        else { return nil }
        let value = SIMD3(x, y, z)
        return value.x.isFinite && value.y.isFinite && value.z.isFinite ? value : nil
    }

    /// Registers an `ObjectReference` native that needs the trap world. Without it
    /// the native stays a traced stub, so the script runs on.
    static func trapWorldReference(
        _ functionName: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (PapyrusNativeCall, TrapWorldTarget) -> PapyrusNativeResult
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "ObjectReference",
            functionName: functionName
        ) { call, context in
            guard
                let world = context.world as? PapyrusWorldStateBridge,
                let receiver = call.receiver, let key = world.referenceKey(for: receiver)
            else { return needsWorld(call) }
            guard let trapWorld = world.trapWorld else {
                context.log.append("Stubbed \(call.qualifiedName)")
                return .deviated(.none, .stubbed)
            }
            return body(call, TrapWorldTarget(world: world, trapWorld: trapWorld, key: key))
        })
    }
}
