// App side of the AI coordinators: packages, the AI & Navigation readout, NPC
// gait clips, and perception. It wires them into the frame loop and answers
// their ports from the session systems. See docs/engine/coordinators.md.

public import OpenSkyActorPresentation
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
public import OpenSkyPerception
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
public protocol AIWorldHost: AnyObject {
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

public final class AIWorldAdapter {
    public let game: any AIWorldHost

    public let seatingHost: any AISeatingHost
    public let detectionSenseHost: any AIDetectionSenseHost
    public let perceptionSenseHost: any AIPerceptionSenseHost
    public let navigationHost: any AINavigationHost
    public let packageMovesHost: any AIPackageMovesHost
    public let packageStateHost: any AIPackageStateHost
    public let packageActsHost: any AIPackageActsHost
    public let bumpsHost: any AIBumpsHost

    public var seating: AISeatingAdapter {
        AISeatingAdapter(game: seatingHost, packageMoves: packageMoves)
    }

    public var detectionSense: AIDetectionSenseAdapter {
        AIDetectionSenseAdapter(game: detectionSenseHost)
    }

    public var perceptionSense: AIPerceptionSenseAdapter {
        AIPerceptionSenseAdapter(game: perceptionSenseHost, detectionSense: detectionSense)
    }

    public var navigation: AINavigationAdapter {
        AINavigationAdapter(game: navigationHost)
    }

    public var packageMoves: AIPackageMovesAdapter {
        AIPackageMovesAdapter(game: packageMovesHost)
    }

    public var packageState: AIPackageStateAdapter {
        AIPackageStateAdapter(game: packageStateHost, packageMoves: packageMoves)
    }

    public var packageActs: AIPackageActsAdapter {
        AIPackageActsAdapter(
            game: packageActsHost, packageMoves: packageMoves, navigation: navigation
        )
    }

    public var bumps: AIBumpsAdapter {
        AIBumpsAdapter(game: bumpsHost)
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
        guard let provider = game.aiRecords, let store = provider.packageStore else {
            return nil
        }
        let settings = provider.gameSettings
        var data = PackageSessionData(store: store, conditionFunctions: .standard)
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
