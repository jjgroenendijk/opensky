// Starting a sound: resolving its descriptor, loading its file, and routing it to the engine.

import Foundation
public import OpenSkyAudio
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface
import simd

private struct ResolvedSoundFile {
    let path: String
    let category: AudioCategory
    let outputModel: FormID?
    let soundCategory: FormID?
    let rumbleSend: SoundDescriptor.RumbleSend?
}

/// One sound waiting for its file: where it plays, and whether it is still wanted.
private struct PendingSound {
    let resolved: ResolvedSoundFile
    /// Nil plays the sound without a position, as region sounds do.
    let position: SIMD3<Float>?
    let kind: String
    let loops: Bool
    let adopt: ((Int) -> Bool)?
    let failed: (() -> Void)?
}

extension WorldAudioPlayback {
    /// Starts the sound when its file is loaded. `adopt` gets the new source's id and
    /// returns false for a sound no longer wanted, which then stops at once.
    func playResolved(
        id: FormID,
        at position: SIMD3<Float>?,
        kind: String,
        loops: Bool = false,
        adopt: ((Int) -> Bool)? = nil,
        failed: (() -> Void)? = nil
    ) {
        guard let resolved = resolveSound(id: id) else {
            director.lastSFXError = "unresolved \(id.description)"
            WorldAudioSoundDirector.logger.debug(
                "[INFO] \(kind, privacy: .public) unresolved: \(id.description, privacy: .public)"
            )
            failed?()
            return
        }
        let pending = PendingSound(
            resolved: resolved, position: position, kind: kind, loops: loops, adopt: adopt,
            failed: failed
        )
        director.assets.request(resolved.path) { [weak director] result in
            guard let director else { return }
            WorldAudioPlayback(director: director).start(result, pending)
        }
    }

    private func start(
        _ result: Result<AudioFileAsset, AssetLoadFailure>,
        _ pending: PendingSound
    ) {
        let resolved = pending.resolved
        do {
            let asset = try result.get()
            let profile = resolved.outputModel.flatMap { director.outputModels?($0) }
            var request = AudioPlayRequest(
                name: resolved.path,
                category: resolved.category,
                worldPosition: pending.position ?? .zero,
                loops: pending.loops,
                soundCategory: resolved.soundCategory
            )
            request.outputModel = profile
            let routing = pending.position == nil ? .nonPositional : AudioRoutingDecision.routing(
                profile: profile,
                channelCount: profile == nil ? asset.channelCount : nil
            )
            let sourceID = try routing == .positional
                ? director.engine.playPositional(asset: asset, request: request)
                : director.engine.playNonPositional(asset: asset, request: request)
            if let adopt = pending.adopt, !adopt(sourceID) {
                director.engine.stopSource(id: sourceID)
                return
            }
            if profile?.allowsRumble == true, let send = resolved.rumbleSend {
                director.rumbleSends[sourceID] = send
            }
            director.lastSFXDescription = resolved.path
            director.lastSFXError = nil
        } catch {
            pending.failed?()
            let reason = String(describing: error)
            director.lastSFXError = reason
            let kind = pending.kind
            WorldAudioSoundDirector.logger.warning(
                "[WARNING] \(kind, privacy: .public) play failed: \(reason, privacy: .public)"
            )
        }
    }

    /// This frame's rumble bus levels: each rumbling sound's send times the level the
    /// listener hears of it now. Ended sources drop out.
    func rumbleLevels() -> SoundRumble {
        guard !director.rumbleSends.isEmpty else { return .silent }
        var small: Float = 0
        var big: Float = 0
        for source in director.engine.sources {
            guard let send = director.rumbleSends[source.id] else { continue }
            let level = director.engine.effectiveGain(of: source) * source.distanceGain
            small += send.small * level
            big += send.big * level
        }
        let playing = Set(director.engine.sources.map(\.id))
        director.rumbleSends = director.rumbleSends.filter { playing.contains($0.key) }
        return SoundRumble(small: small, big: big)
    }

    /// A descriptor with several files plays one of them at random, as the game does.
    private func resolveSound(id: FormID) -> ResolvedSoundFile? {
        guard
            let soundStore = director.soundStore,
            let resolved = attempt({ try soundStore.resolveAny(id) }),
            !resolved.filePaths.isEmpty else { return nil }
        let path = resolved.filePaths[director.regionSounds.pick(count: resolved.filePaths.count)]
        return ResolvedSoundFile(
            path: path,
            category: resolved.audioCategory ?? .effects,
            outputModel: resolved.descriptor.outputModel,
            soundCategory: resolved.descriptor.category,
            rumbleSend: resolved.descriptor.rumbleSend
        )
    }
}
