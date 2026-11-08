import OpenSkyCombat
import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import simd

/// What `MountDragonRidingAdapter` reads from the session.
@MainActor
public protocol MountDragonRidingHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var magic: any MagicPort { get }
    var magicWorld: any MagicWorldPort { get }
    var scripts: any ScriptPort { get }
}

/// Part of `MountWorldAdapter`, over its own narrow host.
public struct MountDragonRidingAdapter {
    public unowned let owner: MountWorldAdapter
    public unowned let game: any MountDragonRidingHost
}

extension MountDragonRidingAdapter {
    /// How far from the view centre, in radians, an actor can be locked.
    public static let lockCone: Float = 0.25
    /// The farthest a rider locks a target from, in units.
    public static let lockRange: Float = 8000

    /// How far from the view centre, in radians, Switch Target looks: about the view.
    public static let switchCone: Float = .pi / 3

    /// The living actor closest to the view centre, inside the lock cone and range.
    public func lockCandidate() -> ReferenceKey? {
        actorsInView(within: Self.lockCone).min { $0.angle < $1.angle }?.key
    }

    /// The living actors in view and range, left to right as the rider sees them.
    public func switchCandidates() -> [ReferenceKey] {
        actorsInView(within: Self.switchCone).sorted { $0.bearing > $1.bearing }.map(\.key)
    }

    /// Each actor inside `cone` of the view centre and the lock range: its angle off the
    /// centre and its bearing, counter-clockwise from the view.
    private func actorsInView(within cone: Float) -> [ActorInView] {
        guard let camera = game.gameSession?.freeFlyCamera else { return [] }
        let mount = owner.mounts.drive?.mount
        let heading = atan2(camera.forward.y, camera.forward.x)
        return game.actorWorld.combatActors().compactMap { actor in
            guard !actor.isDead, actor.key != .player, actor.key != mount else { return nil }
            let offset = actor.feet - camera.position
            let distance = simd_length(offset)
            guard distance > 1, distance <= Self.lockRange else { return nil }
            let angle = acos(min(max(simd_dot(offset / distance, camera.forward), -1), 1))
            guard angle <= cone else { return nil }
            let bearing = remainder(atan2(offset.y, offset.x) - heading, 2 * Float.pi)
            return ActorInView(key: actor.key, angle: angle, bearing: bearing)
        }
    }

    public func allowsFlyingMountLandingRequests() -> Bool {
        let player = game.scripts.bridge?.scriptedState(of: .player)
        return player?.flag(ScriptedStateName.flyingMountLandingRefused) != true
    }

    public func livingActorFeet(_ key: ReferenceKey) -> SIMD3<Float>? {
        guard let actor = game.actorWorld.combatActor(key: key), !actor.isDead else {
            return nil
        }
        return actor.feet
    }

    /// The dragon's strongest breath shout, cast at the target as a named-target spell.
    public func breathe(from mount: ReferenceKey, at target: ReferenceKey) {
        guard
            let holder = game.magicWorld.actorValueHolder(for: mount),
            let spell = game.magic.npcShouts(of: holder).lazy
                .compactMap({ $0.words.last(where: { $0.spell != nil })?.spell }).first
        else { return }
        game.scripts.bridge?.castSpell(spell.key, from: mount, at: target, blame: nil)
    }
}

private struct ActorInView {
    let key: ReferenceKey
    let angle: Float
    let bearing: Float
}
