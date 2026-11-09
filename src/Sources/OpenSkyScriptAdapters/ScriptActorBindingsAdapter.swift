import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `ScriptActorBindingsAdapter` reads from the session.
@MainActor
public protocol ScriptActorBindingsHost: AnyObject {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var aiWorld: any AIWorldPort { get }
    var combat: any CombatPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var packages: any PackagePort { get }
    var perception: any PerceptionPort { get }
    var ragdoll: any RagdollPort { get }
    var runtimeStateWorld: any RuntimeStateWorldPort { get }
    var streamer: (any CellStreamerPort)? { get }
}

/// Part of `ScriptWorldAdapter`, over its own narrow host.
public struct ScriptActorBindingsAdapter {
    public let game: any ScriptActorBindingsHost
    public let skyBindings: ScriptSkyBindingsAdapter
    public let physicsBindings: ScriptPhysicsBindingsAdapter
}

extension ScriptActorBindingsAdapter {}
