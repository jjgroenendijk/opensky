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

    let frames: AIFrameSteps

    var seating: AISeatingAdapter {
        frames.seating
    }

    public var perceptionSense: AIPerceptionSenseAdapter {
        frames.perceptionSense
    }

    var navigation: AINavigationAdapter {
        frames.navigation
    }

    var packageMoves: AIPackageMovesAdapter {
        frames.packageMoves
    }

    var packageState: AIPackageStateAdapter {
        frames.packageState
    }

    public var packageActs: AIPackageActsAdapter {
        frames.packageActs
    }

    public private(set) lazy var worlds = Worlds(self)

    public var bumps: AIBumpsAdapter {
        frames.bumps
    }

    public init(game: some AIWorldHosts) {
        self.game = game
        frames = AIFrameSteps(hosts: game)
    }

    public func packageData() -> PackageSessionData? {
        records.packageData()
    }
}

/// The AI parts over one host, and the frame steps that move NPCs, run packages and
/// perception, and seat actors.
final class AIFrameSteps {
    let hosts: any AIWorldHosts

    init(hosts: any AIWorldHosts) {
        self.hosts = hosts
    }

    var game: any AIWorldHost {
        hosts
    }

    var records: AIRecordReads {
        AIRecordReads(game: game)
    }

    var seating: AISeatingAdapter {
        AISeatingAdapter(game: hosts, packageMoves: packageMoves)
    }

    var detectionSense: AIDetectionSenseAdapter {
        AIDetectionSenseAdapter(game: hosts)
    }

    var perceptionSense: AIPerceptionSenseAdapter {
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

    var packageActs: AIPackageActsAdapter {
        AIPackageActsAdapter(
            game: hosts, packageMoves: packageMoves, navigation: navigation
        )
    }

    var bumps: AIBumpsAdapter {
        AIBumpsAdapter(game: hosts)
    }
}
