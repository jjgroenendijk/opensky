import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import simd

/// What `MountDragonRidingAdapter` reads from the session.
@MainActor
public protocol MountDragonRidingHost: AnyObject, SendableMetatype {
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var magic: any MagicPort { get }
    var magicWorld: any MagicWorldPort { get }
    var mounts: any MountPort { get }
    var scripts: any ScriptPort { get }
}

/// Part of `MountWorldAdapter`, over its own narrow host.
public struct MountDragonRidingAdapter {
    public let game: any MountDragonRidingHost
}

extension MountDragonRidingAdapter {
    /// The living actors in the lock range, nearest first. The range is centred on the
    /// mount's combat target when it has one, else on the player.
    public func lockCandidates() -> [ReferenceKey] {
        guard let session = game.gameSession else { return [] }
        let mount = game.mounts.drive?.mount
        let fought = mount.flatMap { game.combat.loop?.combatTarget(of: $0) }
        let centre = fought.flatMap(livingActorFeet) ?? session.walkController.feetPosition
        let actors = game.actorWorld.combatActors()
            .filter { !$0.isDead && $0.key != .player && $0.key != mount }
            .map { (key: $0.key, feet: $0.feet) }
        return MountTargeting.lockOrder(of: actors, around: centre)
    }

    /// The living actors in view and range, left to right as the rider sees them.
    public func switchCandidates() -> [ReferenceKey] {
        actorsInView(within: MountTargeting.switchCone)
            .sorted { $0.view.bearing > $1.view.bearing }.map(\.key)
    }

    private func actorsInView(within cone: Float) -> [ActorInView] {
        guard let camera = game.gameSession?.freeFlyCamera else { return [] }
        let mount = game.mounts.drive?.mount
        return game.actorWorld.combatActors().compactMap { actor in
            guard !actor.isDead, actor.key != .player, actor.key != mount else { return nil }
            return MountTargeting.view(
                of: actor.feet - camera.position, forward: camera.forward, within: cone
            ).map { ActorInView(key: actor.key, view: $0) }
        }
    }

    public func allowsFlyingMountLandingRequests() -> Bool {
        let player = game.scripts.bridge?.scriptedState(of: .player)
        return player?.flag(ScriptedStateName.flyingMountLandingRefused) != true
    }

    public func livingActorFeet(_ key: ReferenceKey) -> SIMD3<Float>? {
        guard
            key != .player, key != game.mounts.drive?.mount,
            let actor = game.actorWorld.combatActor(key: key), !actor.isDead
        else { return nil }
        return actor.feet
    }

    /// The dragon's strongest breath shout, cast at the target as a named-target spell.
    func breathe(from mount: ReferenceKey, at target: ReferenceKey) {
        guard
            let holder = game.magicWorld.actorValueHolder(for: mount),
            let spell = game.magic.shoutVoice.npcShouts(of: holder).lazy
                .compactMap({ $0.words.last(where: { $0.spell != nil })?.spell }).first
        else { return }
        game.scripts.bridge?.castSpell(spell.key, from: mount, at: target, blame: nil)
    }
}

private struct ActorInView {
    let key: ReferenceKey
    let view: MountTargetView
}
