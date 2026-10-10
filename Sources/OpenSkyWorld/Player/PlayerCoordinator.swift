// The shell of the player: loads both behavior graphs, assembles the body and
// the first-person arms, and rebuilds them when the equipped set changes. A
// load failure is recorded and shown, not retried, because it is a fact about
// the install. See docs/engine/coordinators.md.

import Foundation
import OpenSkyBehavior
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering

/// Owns the player graphs and body state, and reads the world through `PlayerWorld`.
public final class PlayerCoordinator {
    static let logger = EngineLogger(subsystem: "nl.jjgroenendijk.opensky", category: "CellStream")

    let input: CameraInputState
    weak var world: (any PlayerWorld)?
    private var source: (any PlayerRigSource)?
    /// Bumped by each rebuild, so a rig assembled for an older set is dropped.
    private var generation = 0
    /// Held so it stays alive for the session.
    public private(set) var graph: PlayerBehaviorGraph?
    /// Runs beside the third-person graph; the camera mode decides which is drawn.
    public private(set) var firstPersonGraph: PlayerBehaviorGraph?
    /// The set the newest rigs were requested for, to detect a change.
    private var equipped: [FormID]?
    private var appearance: PlayerAppearanceOverride?
    /// The shown rigs' playbacks, which take the draw state each frame.
    private var rigAnimations: [Bool: PlayerAnimationPlayback] = [:]
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
    public func wireBody(source: any PlayerRigSource) -> Bool {
        guard let fileSystem = source.playerAssetFileSystem else {
            failureReason = PlayerBodyError.noFileSystem.localizedDescription
            return false
        }
        let loaded: PlayerBehaviorGraph
        do {
            loaded = try PlayerBehaviorGraph.load(
                fileSystem: fileSystem, clipWorker: Self.clipWorker(fileSystem)
            )
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
                skeletonPath: PlayerBehaviorGraph.firstPersonSkeletonPath,
                clipWorker: Self.clipWorker(fileSystem)
            )
        }
        attach(graph: loaded, firstPerson: firstPerson, source: source)
        return true
    }

    /// Clips read on the shared play-time queue; a state whose clip is still
    /// loading keeps the current pose (docs/decisions/concurrency.md).
    private static func clipWorker(
        _ fileSystem: any GameFileSource
    ) -> SerialAssetLoadWorker<String, SplineBehaviorClip> {
        SerialAssetLoadWorker(load: InstallBehaviorClipSource.load(fileSystem: fileSystem))
    }

    /// Moves finished clip loads and rigs in. Runs at the frame's drain point.
    public func drainClipLoads() {
        graph?.clips.drain()
        firstPersonGraph?.clips.drain()
        drainRigs()
    }

    /// The locomotion bridge drops every write until a graph is attached.
    func attach(
        graph: PlayerBehaviorGraph,
        firstPerson: Result<PlayerBehaviorGraph, any Error>,
        source: any PlayerRigSource
    ) {
        self.graph = graph
        self.source = source
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
        for animation in rigAnimations.values {
            animation.weaponsDrawn = world?.playerWeaponsDrawn ?? false
        }
        guard
            world?.playerEquippedSet != equipped
            || world?.playerAppearanceOverride != appearance
        else { return }
        rebuildBody()
    }

    /// Both rigs are built from one equipped set, so an equip change reaches both.
    func rebuildBody() {
        guard let source, let world, graph != nil else { return }
        let equipped = world.playerEquippedSet
        let appearance = world.playerAppearanceOverride
        self.equipped = equipped
        self.appearance = appearance
        generation += 1
        for firstPerson in firstPersonGraph == nil ? [false] : [false, true] {
            source.requestPlayerRig(PlayerRigRequest(
                generation: generation, firstPerson: firstPerson,
                equipped: equipped, appearance: appearance
            ))
        }
    }

    func drainRigs() {
        guard let source else { return }
        for loaded in source.drainPlayerRigs() where loaded.request.generation == generation {
            if loaded.request.firstPerson {
                showFirstPersonRig(loaded.result)
            } else {
                showBody(loaded.result)
            }
        }
    }

    private func showBody(_ result: Result<PlayerRigAssembly, PlayerBodyError>) {
        guard let graph, let world, let locomotion = world.playerLocomotion else { return }
        switch result {
        case let .success(rig):
            failureReason = nil
            do {
                let body = PlayerBody(rig: rig, skeleton: graph.skeleton, pose: locomotion.pose)
                try world.showPlayerBody(body)
                rigAnimations[false] = body.animation
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
    }

    private func showFirstPersonRig(_ result: Result<PlayerRigAssembly, PlayerBodyError>) {
        guard let firstPersonGraph, let world, let locomotion = world.playerLocomotion else {
            return
        }
        switch result {
        case let .success(assembly):
            firstPersonFailureReason = nil
            let rig = PlayerFirstPersonRig(
                rig: assembly, skeleton: firstPersonGraph.skeleton,
                pose: locomotion.firstPersonPose
            )
            do {
                try world.showFirstPersonRig(rig)
                rigAnimations[true] = rig.animation
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
