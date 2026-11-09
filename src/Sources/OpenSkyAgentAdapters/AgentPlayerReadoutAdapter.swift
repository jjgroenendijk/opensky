import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AgentPlayerReadoutAdapter` reads from the session.
@MainActor
public protocol AgentPlayerReadoutHost: AnyObject {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var controllerRumble: any ControllerRumblePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var magic: any MagicPort { get }
    var perks: any PerkPort { get }
    var player: any PlayerPort { get }
    var playerBeastForm: PlayerBeastForm { get }
    var playerControlLocks: PlayerControlLocks { get }
    var ragdoll: any RagdollPort { get }
    var streamer: any CellStreamerPort { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentPlayerReadoutAdapter {
    public let hub: AgentHub
    public let game: any AgentPlayerReadoutHost
}

extension AgentPlayerReadoutAdapter {
    public func playerState() throws(AgentFailure) -> AgentJSON {
        guard let gameSession = game.gameSession else { throw hub.notReady() }
        let camera = gameSession.freeFlyCamera
        var result: [String: AgentJSON] = [
            "position": .init(camera.position),
            "yaw": .init(MatrixMath.signedDegrees(fromRadians: camera.yaw)),
            "pitch": .init(MatrixMath.degrees(fromRadians: camera.pitch)),
            "movementMode": .string(String(describing: gameSession.movementMode)),
            "cell": hub.actorReadout.cellState(at: camera.position),
            "worldspace": .string(game.streamer.worldspaceEditorID),
            "bodyFailure": .init(game.player.failureReason),
            "form": .string(game.playerBeastForm.rawValue),
            "behaviorProject": .init(game.player.graphProject),
            "behaviorProjectFailure": .init(game.player.raceGraphFailureReason)
        ]
        result.merge(hub.frameReadout.weatherReport(gameSession.weather)) { $1 }
        if let values = game.actorValues.runtime {
            let current = values.current(of: .player)
            let maximum = values.maximums(of: .player)
            result["level"] = .init(values.baselines.playerLevel.level)
            result["health"] = ["current": .init(current.health), "max": .init(maximum.health)]
            result["magicka"] = ["current": .init(current.magicka), "max": .init(maximum.magicka)]
            result["stamina"] = ["current": .init(current.stamina), "max": .init(maximum.stamina)]
        }
        // Abilities such as Rested show here; the game lists them in the magic menu.
        result["spells"] = .array(game.magic.playerKnownSpells().map { spell in
            .string(spell.editorID ?? "\(spell.id)")
        })
        result["perks"] = .array((game.perks.runtime.flatMap { runtime in
            game.actorWorld.actorValueHolder(for: .player).map { runtime.ownedPerks(of: $0) }
        } ?? []).map { .string($0.editorID ?? "\($0.id)") })
        let cloak = game.actorWorld.actorValueHolder(for: .player)
            .flatMap(game.magic.cloakIsRunning)
        result["cloak"] = .string(cloak.map { $0 ? "running" : "suspended" } ?? "none")
        result["firstPerson"] = firstPersonState(gameSession: gameSession)
        result["melee"] = meleeState()
        result.merge(playerStatusState()) { _, new in new }
        result.merge(playerWeaponState(gameSession: gameSession)) { _, new in new }
        let status = gameSession.locomotion.status
        result["graph"] = [
            "attached": .bool(status.graphAvailable),
            "raisedEvents": .array(status.raisedEvents.map(AgentJSON.string)),
            "missingEvents": .array(status.missingEvents.map(AgentJSON.string)),
            "recentEvents": .array(status.recentGraphEvents.map(AgentJSON.string)),
            "activeStates": .array((gameSession.locomotion.graph?.activeStates ?? []).map {
                .string("\($0.machineName ?? "?") / \($0.stateName ?? "?")")
            }),
            "drunk": .bool(gameSession.locomotion.actorState.isDrunk),
            "perkState": gameSession.locomotion.actorState.taggedPerkState
                .map { .string($0.displayName) } ?? .null,
            "iState": gameSession.locomotion.graph?.variable(named: ActorGraphNames.state)
                .map { .init($0.intValue) } ?? .null,
            "iGetUpType": gameSession.locomotion.graph?
                .variable(named: ActorStateGraphNames.getUpType)
                .map { .init($0.intValue) } ?? .null,
            "attackTiming": .object(Dictionary(uniqueKeysWithValues: ActorStateGraphCore
                    .attackTiming.map { entry in
                        let value = gameSession.locomotion.graph?.variable(named: entry.name)
                        return (entry.name, value.map { AgentJSON($0.realValue) } ?? .null)
                    }))
        ]
        return .object(result)
    }

    /// The held staff and the bow zoom.
    private func playerWeaponState(gameSession: any GameSessionPort) -> [String: AgentJSON] {
        var result: [String: AgentJSON] = [:]
        result["staff"] = game.magic.playerStaff().map { held in
            [
                "item": .string("\(held.staff.profile.item)"),
                "enchantment": .string(held.staff.spell.editorID ?? held.staff.profile.name),
                "charge": .init(held.charge.remaining),
                "capacity": .init(held.charge.capacity)
            ]
        } ?? .null
        result["bowZoom"] = [
            "zoomed": .bool(gameSession.bowZoomViewShare < 1),
            "viewShare": .init(gameSession.bowZoomViewShare),
            "timeScale": .init(gameSession.bowZoomTimeScale),
            "fovYDegrees": .init(MatrixMath.degrees(fromRadians: gameSession.viewFOVYRadians)),
            "staminaPauseSeconds": .init(
                game.actorValues.runtime?.regenerationPause(.stamina, of: .player) ?? 0
            )
        ]
        return result
    }

    /// The last fall and rumble, the death phase, and the locked controls.
    private func playerStatusState() -> [String: AgentJSON] {
        let locks = game.playerControlLocks
        return [
            "lastFall": game.combat.lastFall.map { fall in
                [
                    "actor": .string("\(fall.actor)"), "height": .init(fall.height),
                    "speed": .init(fall.speed), "damage": .init(fall.damage)
                ]
            } ?? .null,
            "lastRumble": game.controllerRumble.lastRumble.map { rumble in
                [
                    "big": [.init(rumble.bigSeconds), .init(rumble.bigStrength)],
                    "small": [.init(rumble.smallSeconds), .init(rumble.smallStrength)],
                    "cause": game.controllerRumble.lastRumbleCause.map(AgentJSON.string) ?? .null
                ]
            } ?? .null,
            "soundRumble": [
                "small": .init(game.controllerRumble.soundMotors.small),
                "big": .init(game.controllerRumble.soundMotors.big)
            ],
            "healthCues": hub.render.healthCueState(),
            "death": .string(String(describing: game.ragdoll.playerDeath.phase)),
            "ragdoll": .bool(game.ragdoll.runtime?.world.isRagdolling(.player) == true),
            "eyeTexture": hub.actors.eyeTexture(of: .player),
            "controls": [
                "disabled": .array(locks.disabled.map(\.rawValue).sorted().map(AgentJSON.string)),
                "savingDisabled": .bool(locks.savingDisabled),
                "waitingDisabled": .bool(locks.waitingDisabled),
                "chargenMessage": .bool(locks.showsChargenMessage)
            ]
        ]
    }

    /// `attackState` is the `GetAttackState` value conditions read.
    private func meleeState() -> AgentJSON {
        guard let melee = game.combat.melee else { return .null }
        return [
            "attackPhase": .string(melee.state.attackPhase.rawValue),
            "attackState": .init(game.combat.playerActionFacts?.attackState.rawValue ?? 0),
            "chainWindowOpen": .bool(melee.state.isChainWindowOpen),
            "swingID": .init(melee.state.swingID)
        ]
    }

    private func firstPersonState(gameSession: any GameSessionPort) -> AgentJSON {
        let snapshot = game.player.firstPersonSnapshot
        let rig = gameSession.playerFirstPersonRig
        return [
            "graphAttached": .bool(snapshot.graphAttached),
            "rigAttached": .bool(snapshot.rigAttached),
            "drawn": .bool(snapshot.active),
            "failure": .init(snapshot.failureReason),
            "armModels": .init(snapshot.armModelCount),
            "bonesPosed": .init(rig?.animation.lastUpdatedBoneCount ?? 0),
            "graphUpdates": .init(snapshot.graphUpdates),
            "missingEvents": .array(snapshot.missingEvents.map(AgentJSON.string)),
            "missingVariables": .array(snapshot.missingVariables.map(AgentJSON.string))
        ]
    }
}
