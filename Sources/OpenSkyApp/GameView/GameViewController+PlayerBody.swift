// App-side wiring for the third-person player body (issue #189): loading the
// vanilla behavior graph, assembling the body over the scene provider, handing
// both to the renderer, and rebuilding the body when the player's equipped set
// changes.
//
// It sits beside the streaming wiring rather than inside it because none of it
// is streaming: the graph and the body are built once and outlive every cell.
// What it shares with streaming is the provider, which is the only thing that
// knows the archives and the plugin.

import AppKit
import OSLog

/// What the player-body wiring keeps between frames. Stored on the controller
/// because extensions cannot add state.
struct PlayerBodyBridgeState {
    /// The running graph, held so it stays alive for the session and so the
    /// readout can name it.
    var graph: PlayerBehaviorGraph?
    /// The first-person graph and rig (issue #190). Held beside the
    /// third-person pair rather than replacing it: both run every step and the
    /// camera mode decides which is drawn.
    var firstPersonGraph: PlayerBehaviorGraph?
    /// The equipped set the current body was assembled from, so a change can be
    /// detected without rebuilding every frame.
    var equipped: [FormID]?
    /// Why there is no body, when there is none. Empty once one is attached.
    var failureReason: String?
    /// Why there are no arms, when there are none. Kept apart from
    /// `failureReason` because an install can have a working third-person set
    /// and a broken `_1stperson` one, and reporting one as the other would
    /// send a reader to the wrong files.
    var firstPersonFailureReason: String?
}

extension GameViewController {
    /// Loads the player graph, attaches it to the locomotion bridge, and
    /// assembles the body. A failure at any step is recorded and reported
    /// rather than retried: it is a fact about the install, and a silent retry
    /// loop would hide it behind a stutter.
    func wirePlayerBody(provider: any CellSceneProvider, renderer: Renderer) {
        guard let bodyProvider = provider as? PlayerBodyProviding else {
            playerBodyBridge.failureReason = "the scene provider cannot assemble actors"
            return
        }
        guard let fileSystem = bodyProvider.playerAssetFileSystem else {
            playerBodyBridge.failureReason =
                PlayerBodyError.noFileSystem.localizedDescription
            return
        }
        do {
            let graph = try PlayerBehaviorGraph.load(fileSystem: fileSystem)
            playerBodyBridge.graph = graph
            // The bridge was built with no graph at renderer init, before any
            // provider existed. Attaching one here is the supported path
            // (LocomotionBridge.attach): every write and event was being
            // dropped until now, and nothing was queued to replay.
            renderer.locomotion.attach(graph: graph.instance)
            wireFirstPersonGraph(fileSystem: fileSystem, renderer: renderer)
            rebuildPlayerBody(provider: bodyProvider, renderer: renderer)
        } catch let error as PlayerBehaviorGraphError {
            playerBodyBridge.failureReason =
                PlayerBodyError.behavior(error).localizedDescription
            Self.logger.error(
                "[ERROR] player behavior graph: \(String(describing: error), privacy: .public)"
            )
            return
        } catch {
            playerBodyBridge.failureReason = String(describing: error)
            return
        }
        // Equipment is a world-state write that can come from the panel, a
        // container menu, or a Papyrus script, so the body watches the resulting
        // set rather than any one of those call sites.
        renderer.onFrame.add { [weak self, weak renderer] _ in
            guard let self, let renderer else { return }
            refreshPlayerBodyEquipment(provider: bodyProvider, renderer: renderer)
        }
    }

    /// Loads the `_1stperson` graph and hands it to the bridge (issue #190).
    ///
    /// Failure here is recorded and survived rather than propagated: an
    /// install whose first-person set is missing or malformed still walks,
    /// still renders a third-person body, and simply has no arms — which the
    /// panel says in as many words.
    private func wireFirstPersonGraph(fileSystem: VirtualFileSystem, renderer: Renderer) {
        do {
            let graph = try PlayerBehaviorGraph.load(
                fileSystem: fileSystem,
                behaviorPath: PlayerBehaviorGraph.firstPersonBehaviorPath,
                skeletonPath: PlayerBehaviorGraph.firstPersonSkeletonPath
            )
            playerBodyBridge.firstPersonGraph = graph
            renderer.locomotion.attachFirstPerson(graph: graph.instance)
        } catch let error as PlayerBehaviorGraphError {
            playerBodyBridge.firstPersonFailureReason =
                PlayerBodyError.behavior(error).localizedDescription
            Self.logger.error(
                "[ERROR] first-person graph: \(String(describing: error), privacy: .public)"
            )
        } catch {
            playerBodyBridge.firstPersonFailureReason = String(describing: error)
        }
    }

    /// Assembles a body for the player's current equipped set and attaches it,
    /// then does the same for the first-person arms from the same set — which
    /// is what makes an equip change reach both rigs (issue #190).
    func rebuildPlayerBody(provider: any PlayerBodyProviding, renderer: Renderer) {
        guard let graph = playerBodyBridge.graph else { return }
        let equipped = playerEquippedSet()
        switch provider.makePlayerBody(
            skeleton: graph.skeleton,
            pose: renderer.locomotion.pose,
            equipped: equipped
        ) {
        case let .success(body):
            playerBodyBridge.equipped = equipped
            playerBodyBridge.failureReason = nil
            // The footstep set follows the boots, so it is re-resolved from
            // the same assembly that produced the geometry rather than from a
            // second walk of the equipped list (issue #352).
            updateFootstepSet(from: body)
            do {
                try renderer.setPlayerBody(body)
            } catch {
                playerBodyBridge.failureReason = String(describing: error)
                Self.logger.error(
                    "[ERROR] player body attach: \(String(describing: error), privacy: .public)"
                )
            }
        case let .failure(error):
            playerBodyBridge.failureReason = error.localizedDescription
            Self.logger.warning(
                "player body: \(String(describing: error), privacy: .public)"
            )
        }
        rebuildFirstPersonRig(provider: provider, renderer: renderer, equipped: equipped)
    }

    private func rebuildFirstPersonRig(
        provider: any PlayerBodyProviding,
        renderer: Renderer,
        equipped: [FormID]?
    ) {
        guard let graph = playerBodyBridge.firstPersonGraph else { return }
        switch provider.makePlayerFirstPersonRig(
            skeleton: graph.skeleton,
            pose: renderer.locomotion.firstPersonPose,
            equipped: equipped
        ) {
        case let .success(rig):
            playerBodyBridge.firstPersonFailureReason = nil
            do {
                try renderer.setPlayerFirstPersonRig(rig)
            } catch {
                let text = String(describing: error)
                playerBodyBridge.firstPersonFailureReason = text
                Self.logger.error(
                    "[ERROR] first-person arms attach: \(text, privacy: .public)"
                )
            }
        case let .failure(error):
            playerBodyBridge.firstPersonFailureReason = error.localizedDescription
            Self.logger.warning(
                "first-person arms: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Rebuilds the body when the equipped set changed since it was assembled.
    /// One array comparison per frame; the rebuild itself is rare.
    private func refreshPlayerBodyEquipment(
        provider: any PlayerBodyProviding,
        renderer: Renderer
    ) {
        let equipped = playerEquippedSet()
        guard equipped != playerBodyBridge.equipped else { return }
        rebuildPlayerBody(provider: provider, renderer: renderer)
    }

    /// The player's equipped set, or nil while nothing has touched its
    /// inventory — nil resolves through the plugin `defaultOutfit` chain, which
    /// is what dresses the player before the first equip (issue #178).
    private func playerEquippedSet() -> [FormID]? {
        guard
            let equipment = worldItems.equipment,
            equipment.inventory.hasRuntimeInventory(InventoryHolder.player)
        else { return nil }
        return equipment.equipped(on: InventoryHolder.player)
    }
}
