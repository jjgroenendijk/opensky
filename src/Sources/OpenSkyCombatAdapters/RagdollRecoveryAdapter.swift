import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombat
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `RagdollRecoveryAdapter` reads from the session.
@MainActor
public protocol RagdollRecoveryHost: AnyObject, SendableMetatype {
    var actorGraphWorld: any ActorGraphWorldPort { get }
    var actorValues: any ActorValuePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var hud: any HUDPort { get }
    var mapWorld: any MapWorldPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var combatRecords: (any CombatRecordsPort)? { get }
}

/// Part of `RagdollWorldAdapter`, over its own narrow host.
public struct RagdollRecoveryAdapter {
    public let game: any RagdollRecoveryHost
    public let poseReads: RagdollPoseReadsAdapter
}

extension RagdollRecoveryAdapter {
    /// An essential actor always bleeds out. A protected one bleeds out unless the
    /// player dealt the last blow (UESP "Skyrim:Protected NPCs").
    public func zeroHealthOutcome(
        of key: ReferenceKey,
        killer: ReferenceKey?
    ) -> ZeroHealthOutcome {
        guard let bridge = game.scripts.bridge else { return .dies }
        if bridge.scriptedState(of: key).flag(ScriptedStateName.deferredKill) == true {
            return .deferred
        }
        let flags = bridge.actorFlags(of: key) ?? []
        if flags.contains(.essential) {
            return .bleedsOut
        }
        if killer != .player, flags.contains(.protected) {
            return .bleedsOut
        }
        return .dies
    }

    public func healthFraction(of key: ReferenceKey) -> Float? {
        guard let values = game.actorValues.runtime, let holder = poseReads.holder(of: key) else {
            return nil
        }
        return values.fractions(of: holder)[.health]
    }

    public func bleedoutThreshold(of key: ReferenceKey) -> Float? {
        guard
            let base = game.streamer.referenceEntry(key: key)?.placedActor?.base,
            let resolver = game.combatRecords?.actorValueBaselines?.resolver
        else { return nil }
        return resolver.characterClass(ofBase: base)?.bleedoutDefault
    }

    public func blocksBleedoutRecovery(of key: ReferenceKey) -> Bool {
        game.scripts.bridge?.scriptedState(of: key)
            .flag(ScriptedStateName.noBleedoutRecovery) == true
    }

    public func restoreHealthShare(_ share: Float, of key: ReferenceKey) {
        guard
            let values = game.actorValues.runtime,
            let holder = poseReads.holder(of: key) else { return }
        let missing = values.maximums(of: holder)[.health] - values.current(of: holder)[.health]
        let amount = min(values.maximums(of: holder)[.health] * share, missing)
        if amount > 0 {
            values.restore(.health, by: amount, on: holder)
        }
    }

    public func enterBleedout(_ key: ReferenceKey) {
        game.scripts.bridge?.updateScriptedState(of: key) {
            $0.setFlag(ScriptedStateName.bleedingOut, true)
        }
        _ = game.actorGraphWorld.graphs.raise(RagdollGraphNames.bleedOutStart, on: key)
        _ = game.scripts.bridge?.stopActorCombat(key)
        game.scripts.runtime?.queueEnterBleedout(actor: key)
        announceWoundedTeammate(key)
    }

    /// OpenSky's reading of `sEssentialCharacterDown`: a follower going down is named.
    private func announceWoundedTeammate(_ key: ReferenceKey) {
        let streamer = game.streamer
        guard
            game.scripts.bridge?.scriptedState(of: key)
                .flag(ScriptedStateName.playerTeammate) == true,
            let form = streamer.referenceEntry(key: key)?.formID,
            let name = streamer.interactionName(reference: form), !name.isEmpty
        else { return }
        let down = game.mapWorld.settingTexts(PlayerDeathText.self)[.essentialDown]
        game.hud.showNotification("\(name) \(down)")
    }

    /// The actor stands up with full health (UESP "Skyrim:Essential NPCs").
    public func leaveBleedout(_ key: ReferenceKey) {
        game.scripts.bridge?.updateScriptedState(of: key) {
            $0.setFlag(ScriptedStateName.bleedingOut, nil)
        }
        if let values = game.actorValues.runtime, let holder = poseReads.holder(of: key) {
            let missing = values.maximums(of: holder)[.health] - values.current(of: holder)[.health]
            if missing > 0 {
                values.restore(.health, by: missing, on: holder)
            }
        }
        _ = game.actorGraphWorld.graphs.raise(RagdollGraphNames.bleedOutStop, on: key)
    }

    /// The actor stops where it falls, so no package walks its capsule away. The player's
    /// controls lock, and a first-person view steps out to show the fall.
    public func enterKnockdown(_ key: ReferenceKey) {
        guard key != .player else {
            if game.gameSession?.movementMode == .walk {
                game.gameSession?.setMovementMode(.thirdPerson)
            }
            game.gameSession?.locomotion.raise(RagdollGraphNames.ragdollInstant)
            return
        }
        _ = game.streamer.takeRiddenActor(key)
        _ = game.actorGraphWorld.graphs.raise(RagdollGraphNames.ragdollInstant, on: key)
    }

    /// The graph's `iGetUpType` already reads 2 in water, so only the event is raised.
    public func getUp(_ key: ReferenceKey, feet: SIMD3<Float>, yaw: Float?) {
        guard key != .player else {
            game.gameSession?.placePlayerFeet(at: feet)
            game.gameSession?.locomotion.raise(RagdollGraphNames.getUpStart)
            return
        }
        do {
            let streamer = game.streamer
            let facing = yaw ?? streamer.riddenHold(of: key)?.yaw ?? 0
            streamer.steerRiddenActor(key, to: feet, yaw: facing)
        }
        _ = game.actorGraphWorld.graphs.raise(RagdollGraphNames.getUpStart, on: key)
    }

    public func endKnockdown(_ key: ReferenceKey) {
        guard key != .player else { return }
        _ = game.streamer.releaseRiddenActor(key)
    }

    public func getUpDuration(of key: ReferenceKey) -> Float? {
        let graph = key == .player
            ? game.gameSession?.locomotion.graph
            : game.actorGraphWorld.graphs.instance(of: key)
        guard let duration = graph?.physicsRequests.getUp?.duration, duration > 0 else {
            return nil
        }
        return duration
    }
}
