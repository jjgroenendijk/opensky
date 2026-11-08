// App side of the AI coordinators: packages, the AI & Navigation readout, NPC
// gait clips, and perception. It wires them into the frame loop and answers
// their ports from the session systems. See docs/engine/coordinators.md.

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
public import OpenSkyAIPackages
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDiagnostics
import OpenSkyDialogue
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyNavigation
public import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AIWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol AIWorldHost: AnyObject {
    var followerCommands: any FollowerCommandPort { get }
    var effectsWorld: any EffectsWorldPort { get }
    var actorGraphWorld: any ActorGraphWorldPort { get }
    var combat: any CombatPort { get }
    var npcAnimation: any NPCAnimationPort { get }
    var packages: any PackagePort { get }
    var scripts: any ScriptPort { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

public final class AIWorldAdapter {
    public unowned let game: any AIWorldHost

    public let seatingHost: any AISeatingHost
    public let detectionSenseHost: any AIDetectionSenseHost
    public let perceptionSenseHost: any AIPerceptionSenseHost
    public let navigationHost: any AINavigationHost
    public let packageMovesHost: any AIPackageMovesHost
    public let packageStateHost: any AIPackageStateHost
    public let packageActsHost: any AIPackageActsHost
    public let bumpsHost: any AIBumpsHost

    public var seating: AISeatingAdapter {
        AISeatingAdapter(owner: self, game: seatingHost)
    }

    public var detectionSense: AIDetectionSenseAdapter {
        AIDetectionSenseAdapter(
            owner: self,
            game: detectionSenseHost
        )
    }

    public var perceptionSense: AIPerceptionSenseAdapter {
        AIPerceptionSenseAdapter(
            owner: self,
            game: perceptionSenseHost
        )
    }

    public var navigation: AINavigationAdapter {
        AINavigationAdapter(owner: self, game: navigationHost)
    }

    public var packageMoves: AIPackageMovesAdapter {
        AIPackageMovesAdapter(
            owner: self,
            game: packageMovesHost
        )
    }

    public var packageState: AIPackageStateAdapter {
        AIPackageStateAdapter(
            owner: self,
            game: packageStateHost
        )
    }

    public var packageActs: AIPackageActsAdapter {
        AIPackageActsAdapter(owner: self, game: packageActsHost)
    }

    public var bumps: AIBumpsAdapter {
        AIBumpsAdapter(owner: self, game: bumpsHost)
    }

    public init(game: some AIWorldHost & AISeatingHost & AIDetectionSenseHost &
        AIPerceptionSenseHost &
        AINavigationHost & AIPackageMovesHost & AIPackageStateHost & AIPackageActsHost &
        AIBumpsHost)
    {
        seatingHost = game
        detectionSenseHost = game
        perceptionSenseHost = game
        navigationHost = game
        packageMovesHost = game
        packageStateHost = game
        packageActsHost = game
        bumpsHost = game
        self.game = game
    }

    public func packageData() -> PackageSessionData? {
        guard let provider = game.worldData, let store = provider.packageStore else {
            return nil
        }
        let settings = provider.gameSettings
        var data = PackageSessionData(store: store)
        data.guardWarnings = GuardWarningSettings.resolve(store: settings)
        data.sandboxSettings = SandboxSettings.resolve(store: settings)
        data.bumpSettings = BumpReactionSettings.resolve(store: settings)
        data.followSettings = FollowSettings.resolve(store: settings)
        return data
    }
}

extension AIWorldAdapter: PackageWorld {}

extension AIWorldAdapter {}

extension AIWorldAdapter: AINavigationWorld {}

extension AIWorldAdapter: NPCAnimationWorld {}

extension AIWorldAdapter: PerceptionSessionWorld {}

extension AIWorldAdapter: AIWorldPort {}
