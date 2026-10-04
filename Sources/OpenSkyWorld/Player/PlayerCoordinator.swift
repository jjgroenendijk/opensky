// The shell of the player: loads both behavior graphs, assembles the body and
// the first-person arms, and rebuilds them when the equipped set changes. A
// load failure is recorded and shown, not retried, because it is a fact about
// the install. See docs/engine/coordinators.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import OSLog

/// Owns the player graphs and body state, and reads the world through `PlayerWorld`.
public final class PlayerCoordinator {
    static let logger = Logger(subsystem: "nl.jjgroenendijk.opensky", category: "CellStream")

    let input: CameraInputState
    weak var world: (any PlayerWorld)?
    private var provider: (any PlayerBodyProviding)?
    /// Held so it stays alive for the session.
    public private(set) var graph: PlayerBehaviorGraph?
    /// Runs beside the third-person graph; the camera mode decides which is drawn.
    public private(set) var firstPersonGraph: PlayerBehaviorGraph?
    /// The set the current body was assembled from, to detect a change.
    private var equipped: [FormID]?
    private var appearance: PlayerAppearanceOverride?
    /// Why there is no body, when there is none.
    public private(set) var failureReason: String?
    /// Kept apart from `failureReason`: an install can have a working
    /// third-person set and a broken `_1stperson` one.
    public private(set) var firstPersonFailureReason: String?

    public init(input: CameraInputState) {
        self.input = input
    }

    public func attach(world: any PlayerWorld) {
        self.world = world
    }

    /// Loads both graphs and assembles the body.
    /// - Returns: true when the third-person graph is attached, so the caller
    ///   should call `refreshBody()` every frame.
    public func wireBody(provider: any WorldDataProviding) -> Bool {
        guard let bodyProvider = provider as? PlayerBodyProviding else {
            failureReason = "the scene provider cannot assemble actors"
            return false
        }
        guard let fileSystem = bodyProvider.playerAssetFileSystem else {
            failureReason = PlayerBodyError.noFileSystem.localizedDescription
            return false
        }
        let loaded: PlayerBehaviorGraph
        do {
            loaded = try PlayerBehaviorGraph.load(fileSystem: fileSystem)
        } catch let error as PlayerBehaviorGraphError {
            failureReason = PlayerBodyError.behavior(error).localizedDescription
            Self.logger.error(
                "[ERROR] player behavior graph: \(String(describing: error), privacy: .public)"
            )
            return false
        } catch {
            failureReason = String(describing: error)
            return false
        }
        let firstPerson = Result {
            try PlayerBehaviorGraph.load(
                fileSystem: fileSystem,
                behaviorPath: PlayerBehaviorGraph.firstPersonBehaviorPath,
                skeletonPath: PlayerBehaviorGraph.firstPersonSkeletonPath
            )
        }
        attach(graph: loaded, firstPerson: firstPerson, provider: bodyProvider)
        return true
    }

    /// The locomotion bridge drops every write until a graph is attached.
    func attach(
        graph: PlayerBehaviorGraph,
        firstPerson: Result<PlayerBehaviorGraph, any Error>,
        provider: any PlayerBodyProviding
    ) {
        self.graph = graph
        self.provider = provider
        world?.playerLocomotion?.attach(graph: graph.instance)
        switch firstPerson {
        case let .success(firstPersonGraph):
            self.firstPersonGraph = firstPersonGraph
            world?.playerLocomotion?.attachFirstPerson(graph: firstPersonGraph.instance)
        case let .failure(error as PlayerBehaviorGraphError):
            firstPersonFailureReason = PlayerBodyError.behavior(error).localizedDescription
            Self.logger.error(
                "[ERROR] first-person graph: \(String(describing: error), privacy: .public)"
            )
        case let .failure(error):
            firstPersonFailureReason = String(describing: error)
        }
        rebuildBody()
    }

    /// Equipment changes come from the panel, a menu, or a script, so the body
    /// watches the resulting set. One array comparison per frame.
    public func refreshBody() {
        guard
            world?.playerEquippedSet != equipped
            || world?.playerAppearanceOverride != appearance
        else { return }
        rebuildBody()
    }

    /// Both rigs are built from one equipped set, so an equip change reaches both.
    func rebuildBody() {
        guard
            let graph,
            let provider,
            let world,
            let locomotion = world.playerLocomotion
        else { return }
        let equipped = world.playerEquippedSet
        let appearance = world.playerAppearanceOverride
        switch provider.makePlayerBody(
            skeleton: graph.skeleton, pose: locomotion.pose, equipped: equipped,
            appearance: appearance
        ) {
        case let .success(body):
            self.equipped = equipped
            self.appearance = appearance
            failureReason = nil
            do {
                try world.showPlayerBody(body)
            } catch {
                failureReason = String(describing: error)
                Self.logger.error(
                    "[ERROR] player body attach: \(String(describing: error), privacy: .public)"
                )
            }
        case let .failure(error):
            failureReason = error.localizedDescription
            Self.logger.warning("player body: \(String(describing: error), privacy: .public)")
        }
        rebuildFirstPersonRig(
            provider: provider, world: world, equipped: equipped, appearance: appearance
        )
    }

    private func rebuildFirstPersonRig(
        provider: any PlayerBodyProviding,
        world: any PlayerWorld,
        equipped: [FormID]?,
        appearance: PlayerAppearanceOverride?
    ) {
        guard let firstPersonGraph, let locomotion = world.playerLocomotion else { return }
        switch provider.makePlayerFirstPersonRig(
            skeleton: firstPersonGraph.skeleton,
            pose: locomotion.firstPersonPose,
            equipped: equipped,
            appearance: appearance
        ) {
        case let .success(rig):
            firstPersonFailureReason = nil
            do {
                try world.showFirstPersonRig(rig)
            } catch {
                let text = String(describing: error)
                firstPersonFailureReason = text
                Self.logger.error("[ERROR] first-person arms attach: \(text, privacy: .public)")
            }
        case let .failure(error):
            firstPersonFailureReason = error.localizedDescription
            Self.logger.warning("first-person arms: \(String(describing: error), privacy: .public)")
        }
    }
}
