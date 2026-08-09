// App wiring for the engine-owned NPC mover (issue #423): persistence, live
// draw deltas, and the measured kinematic gait-clip drive.

import AppKit

struct NPCMovementBridgeState {
    var clips: [String: ActorAnimationClip] = [:]
    var unresolvableClips: Set<String> = []
}

extension GameViewController {
    func wireNPCMovement(renderer: Renderer, streamer: CellStreamer) {
        streamer.npcMovementConfiguration = renderer.locomotion.configuration
        let worldState = worldState
        streamer.onNPCMovementPersist = { persistence in
            worldState.set(
                persistence.transform,
                for: persistence.actor,
                in: persistence.cell
            )
        }
        streamer.onNPCPosesChanged = { [weak renderer] deltas in
            renderer?.npcInstanceDeltas = deltas
        }
        streamer.onNPCLocomotionDrive = { [weak self] update in
            self?.driveNPCAnimation(update)
        }
    }

    private func driveNPCAnimation(_ update: NPCLocomotionDriveUpdate) {
        guard let playback = actorPlayback(for: update.actor) else { return }
        guard update.intent != .still else {
            playback.setLocomotionClip(nil)
            return
        }
        playback.setLocomotionClip(gaitClip(update.gait, playback: playback))
    }

    private func gaitClip(
        _ gait: LocomotionGait,
        playback: ActorAnimationPlayback
    ) -> ActorAnimationClip? {
        guard
            let fileSystem = audioFileSystem,
            let path = ActorAnimationClipLoader.gaitAnimationPath(gait, female: playback.female)
        else { return nil }
        let cacheKey = "\(playback.clip.skeletonMeshPath)#\(path)"
        guard !npcMovementBridge.unresolvableClips.contains(cacheKey) else { return nil }
        if let cached = npcMovementBridge.clips[cacheKey] {
            return cached
        }
        guard
            let clip = try? ActorAnimationClipLoader.clip(
                skeletonMeshPath: playback.clip.skeletonMeshPath,
                animationPath: path,
                readHKX: { filePath in try HKXFile(data: fileSystem.contents(forPath: filePath)) }
            )
        else {
            npcMovementBridge.unresolvableClips.insert(cacheKey)
            return nil
        }
        npcMovementBridge.clips[cacheKey] = clip
        return clip
    }
}
