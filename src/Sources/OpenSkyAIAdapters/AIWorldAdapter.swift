// App side of the AI coordinators: packages, the AI & Navigation readout, NPC
// gait clips, and perception. It wires them into the frame loop and answers
// their ports from the session systems. See docs/engine/coordinators.md.

import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyNavigation
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AIWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol AIWorldHost: AnyObject, SendableMetatype {
    var followerCommands: any FollowerCommandPort { get }
    var effectsWorld: any EffectsWorldPort { get }
    var actorGraphWorld: any ActorGraphWorldPort { get }
    var combat: any CombatPort { get }
    var npcAnimation: any NPCAnimationPort { get }
    var packages: any PackagePort { get }
    var scripts: any ScriptPort { get }
    var aiRecords: (any AIRecordsPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Every host an `AIWorldAdapter` part reads, all one object.
public typealias AIWorldHosts = AIBumpsHost & AIDetectionSenseHost & AINavigationHost &
    AIPackageActsHost & AIPackageMovesHost & AIPackageStateHost &
    AIPerceptionSenseHost & AISeatingHost & AIWorldHost

public final class AIWorldAdapter {
    public let game: any AIWorldHost

    let hosts: any AIWorldHosts

    var seating: AISeatingAdapter {
        AISeatingAdapter(game: hosts, packageMoves: packageMoves)
    }

    var detectionSense: AIDetectionSenseAdapter {
        AIDetectionSenseAdapter(game: hosts)
    }

    public var perceptionSense: AIPerceptionSenseAdapter {
        AIPerceptionSenseAdapter(game: hosts, detectionSense: detectionSense)
    }

    var navigation: AINavigationAdapter {
        AINavigationAdapter(game: hosts)
    }

    var packageMoves: AIPackageMovesAdapter {
        AIPackageMovesAdapter(game: hosts)
    }

    var packageState: AIPackageStateAdapter {
        AIPackageStateAdapter(game: hosts, packageMoves: packageMoves)
    }

    public var packageActs: AIPackageActsAdapter {
        AIPackageActsAdapter(
            game: hosts, packageMoves: packageMoves, navigation: navigation
        )
    }

    public private(set) lazy var worlds = Worlds(self)

    public var bumps: AIBumpsAdapter {
        AIBumpsAdapter(game: hosts)
    }

    public init(game: some AIWorldHosts) {
        hosts = game
        self.game = game
    }

    public func packageData() -> PackageSessionData? {
        records.packageData()
    }
}
