// The audio engine, the three world directors, and the World > Audio lab
// state. Rules live in `AudioLabCore`; the app answers `AudioWorld`
// (docs/engine/coordinators.md).

import Foundation
import OpenSkyAudio
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import simd

/// What the audio coordinator reads from the running session.
public protocol AudioWorld: AnyObject {
    /// The stores the directors resolve against; nil without game data.
    var audioWorldData: (any WorldDataProviding)? { get }
    var audioFileSystem: (any GameFileSource)? { get }
    var audioListenerPose: (position: SIMD3<Float>, yaw: Float) { get }
    /// Nil before the player body is assembled.
    var playerFeetArmatures: [FormID]? { get }
    /// Both nil without a renderer.
    var playerGait: LocomotionGait? { get }
    var playerFeetPosition: SIMD3<Float>? { get }
    var audioAnimationTime: Float { get }
    /// The lip-sync driver of the actor the dialogue menu faces.
    func lipSyncTarget() -> LipSyncPlayback?
    /// The renderer's audio tick drives the listener, the playlist, and footsteps.
    func installAudio(
        engine: WorldAudioEngine,
        music: WorldMusicDirector,
        footsteps: WorldAudioFootstepDirector
    )
}

public final class AudioCoordinator {
    public private(set) var engine: WorldAudioEngine?
    public private(set) var soundDirector: WorldAudioSoundDirector?
    public private(set) var musicDirector: WorldMusicDirector?
    public private(set) var footstepDirector: WorldAudioFootstepDirector?
    /// Effect, footstep, and ambience files, shared by the directors. Nil before audio is on.
    public private(set) var assets: AudioAssetLoader?
    /// Voice line bytes for the lab trigger, read off the main actor.
    var voiceFiles: AssetLoader<String, Data>?
    weak var world: (any AudioWorld)?
    /// Enumerating every archive entry is not free, so the list builds off the main actor.
    var musicFileNames: [String]?
    /// Set once the list is requested; a test awaits it.
    var musicListing: Task<Void, Never>?
    var voice = VoiceLabState()

    public init() {}

    public func attach(world: any AudioWorld) {
        self.world = world
    }

    /// Called once the engine exists, so stored volumes reach it.
    public var onEngineBuilt: (() -> Void)?

    /// The first enable builds the engine and the directors once.
    public var audioEnabled: Bool {
        get { engine?.isEnabled ?? false }
        set {
            if newValue, engine == nil {
                buildEngine()
                onEngineBuilt?()
            }
            engine?.isEnabled = newValue
        }
    }

    public func updateFootstepSet(feetArmatures: [FormID]) {
        footstepDirector?.updateFootstepSet(feetArmatures: feetArmatures)
    }

    /// Empty until the list is built; the panel refreshes and then shows it.
    public var selectableAudioFileNames: [String] {
        if let musicFileNames {
            return musicFileNames
        }
        if musicListing == nil, let files = world?.audioFileSystem {
            musicListing = Task { [weak self] in
                let names = await Self.listPaths(files: files, AudioLabCore.musicPaths(in:))
                self?.musicFileNames = names
            }
        }
        return []
    }

    @concurrent
    nonisolated static func listPaths(
        files: any GameFileSource,
        _ select: @Sendable ([VFSEntry]) -> [String]
    ) async -> [String] {
        select(files.archiveEntries())
    }

    /// Nil when the play started or waits for its file; else the reason.
    public func playAudioFile(named name: String) -> String? {
        guard let engine, engine.isRunning, let assets else {
            return "audio engine is not running"
        }
        var reason: String?
        let position = triggerPosition()
        assets.request(name) { result in
            do {
                // Vanilla `.xwm` is all music, but the trigger tests the positional path.
                try engine.playPositional(asset: result.get(), request: AudioPlayRequest(
                    name: name, category: .effects, worldPosition: position
                ))
            } catch {
                reason = String(describing: error)
            }
        }
        return reason
    }

    /// The frame's drain point: loaded sound files start the plays that waited.
    public func drainLoads() {
        assets?.drain()
        musicDirector?.drainLoads()
        drainVoice()
    }

    func triggerPosition() -> SIMD3<Float> {
        let pose = world?.audioListenerPose ?? (.zero, 0)
        return AudioLabCore.triggerPosition(camera: pose.position, yaw: pose.yaw)
    }

    private func buildEngine() {
        let engine = WorldAudioEngine()
        self.engine = engine
        let provider = world?.audioWorldData
        let audioData = provider as? AudioDataProviding
        let weatherStore = (provider as? WeatherProviding)?.weatherSystem?.store
        let fileSystem = world?.audioFileSystem
        let assets = fileSystem.map { AudioAssetLoader(files: $0) }
            ?? AudioAssetLoader(immediate: { throw VFSError.fileNotFound(path: $0) })
        self.assets = assets
        voiceFiles = fileSystem.map { files in
            AssetLoader { path in try files.contents(forPath: path) }
        }
        let director = WorldAudioSoundDirector(
            engine: engine,
            soundStore: audioData?.soundStore,
            weatherStore: weatherStore,
            aspcStore: audioData?.aspcStore,
            assets: assets
        )
        if let records = (provider as? EffectDataProviding)?.effectRecords {
            director.wireEffectRecords(records)
        }
        soundDirector = director
        let music = WorldMusicDirector(
            engine: engine,
            musicStore: audioData?.musicStore,
            weatherStore: weatherStore,
            fileSystem: fileSystem
        )
        musicDirector = music
        let footsteps = WorldAudioFootstepDirector(
            engine: engine,
            footstepStore: audioData?.footstepStore,
            soundStore: audioData?.soundStore,
            assets: assets
        )
        footsteps.materialTypes = audioData?.materialTypes ?? .empty
        footstepDirector = footsteps
        world?.installAudio(engine: engine, music: music, footsteps: footsteps)
        // The body is usually assembled before audio is on, so do not wait for an equip change.
        if let armatures = world?.playerFeetArmatures {
            footsteps.updateFootstepSet(feetArmatures: armatures)
        }
    }
}

extension PlayerBody {
    /// Worn parts come before skin parts, so boots outrank the bare foot. Nothing
    /// worn lands on the naked-feet armature, which vanilla points at the barefoot set.
    public var feetArmatures: [FormID] {
        assembly.visual.parts
            .filter { $0.slots.contains(.feet) }
            .map(\.armature)
    }
}
