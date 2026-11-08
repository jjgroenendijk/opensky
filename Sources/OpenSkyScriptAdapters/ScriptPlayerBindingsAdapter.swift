import Foundation
import MetalKit
import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkyScripting
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `ScriptPlayerBindingsAdapter` reads from the session.
@MainActor
public protocol ScriptPlayerBindingsHost: AnyObject {
    var actorGraphs: any ActorGraphPort { get }
    var actorValues: any ActorValuePort { get }
    var crime: any CrimePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var magic: any MagicPort { get }
    var packages: any PackagePort { get }
    var player: any PlayerPort { get }
    var ragdoll: any RagdollPort { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `ScriptWorldAdapter`, over its own narrow host.
public struct ScriptPlayerBindingsAdapter {
    public unowned let owner: ScriptWorldAdapter
    public unowned let game: any ScriptPlayerBindingsHost
}

extension ScriptPlayerBindingsAdapter {
    public func wirePlayerRules(_ hooks: inout PapyrusGameNatives) {
        hooks.setGodMode = { [weak game] isOn in game?.actorValues.runtime?.setGodMode(isOn) }
        hooks.setFootIK = { [weak game] isOn in
            game?.actorGraphs.footIk = isOn
            game?.gameSession?.locomotion.footIk = isOn
        }
        hooks.clearPrison = { [weak game] in game?.crime.clearPrison() }
        hooks.setPlayerReportsCrime = { [weak game] reports in
            game?.crime.reporter?.setReportsPlayerCrimes(reports)
        }
        hooks.playerGrabbedReference = { [weak game] in game?.magic.playerGrabbedReference }
        hooks.packageLocation = { [weak game] actor in game?.packages.packageLocation(of: actor) }
        hooks.forceRagdoll = { [weak game] key in
            game?.ragdoll.runtime?.activate(key, instant: true) ?? false
        }
        hooks.addBallAndSocket = { [weak owner] first, second in
            owner?.physicsBindings.addBallAndSocket(Self.linkEnd(first), Self.linkEnd(second))
                ?? .returned(.boolean(false))
        }
        hooks.removeConstraints = { [weak owner] first, second in
            owner?.physicsBindings
                .removeConstraints(Self.linkEnd(first), Self.linkEnd(second)) ?? false
        }
        hooks.setEyeTexture = { [weak game] actor, textureSet in
            guard let game, let set = game.scripts.bridge?.localFormID(of: textureSet) else {
                return false
            }
            if actor == .player || actor == .playerReference {
                game.player.eyeTextureSet = set
                return true
            }
            guard let cell = game.streamer?.cellLocation(of: actor) else { return false }
            game.worldState.setEyeTexture(set, for: actor, in: cell)
            return true
        }
    }

    private static func linkEnd(_ end: PapyrusConstraintEnd) -> PhysicsLinkEnd {
        PhysicsLinkEnd(reference: end.reference, node: end.node, offset: end.offset)
    }
}
