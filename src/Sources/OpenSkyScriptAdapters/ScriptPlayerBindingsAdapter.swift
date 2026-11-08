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
import OpenSkyScriptingInterface
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
    static func linkEnd(_ end: PapyrusConstraintEnd) -> PhysicsLinkEnd {
        PhysicsLinkEnd(reference: end.reference, node: end.node, offset: end.offset)
    }
}
