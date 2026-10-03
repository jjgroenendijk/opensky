// The audio engine, the three world directors, and the World > Audio lab
// state. Rules live in `AudioLabCore`; the app answers `AudioWorld`
// (docs/engine/coordinators.md).

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
    weak var world: (any AudioWorld)?
    /// Enumerating every archive entry is not free.
    var musicFileNames: [String]?
    var voice = VoiceLabState()

    public init() {}

    public func attach(world: any AudioWorld) {
        self.world = world
    }

    /// The first enable builds the engine and the directors once.
    public var audioEnabled: Bool {
        get { engine?.isEnabled ?? false }
        set {
            if newValue, engine == nil {
                buildEngine()
            }
            engine?.isEnabled = newValue
        }
    }

    public func updateFootstepSet(feetArmatures: [FormID]) {
        footstepDirector?.updateFootstepSet(feetArmatures: feetArmatures)
    }

    public var selectableAudioFileNames: [String] {
        if let musicFileNames {
            return musicFileNames
        }
        let names = AudioLabCore.musicPaths(in: world?.audioFileSystem?.archiveEntries() ?? [])
        musicFileNames = names
        return names
    }

    public func playAudioFile(named name: String) -> String? {
        guard let engine, engine.isRunning else {
            return "audio engine is not running"
        }
        guard let fileSystem = world?.audioFileSystem else {
            return "no game data"
        }
        do {
            let data = try fileSystem.contents(forPath: name)
            // Vanilla `.xwm` is all music, but the trigger tests the positional path.
            try engine.playPositional(fileData: data, request: AudioPlayRequest(
                name: name, category: .effects, worldPosition: triggerPosition()
            ))
            return nil
        } catch {
            return String(describing: error)
        }
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
        let director = WorldAudioSoundDirector(
            engine: engine,
            soundStore: audioData?.soundStore,
            weatherStore: weatherStore,
            aspcStore: audioData?.aspcStore,
            fileSystem: fileSystem
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
            fileSystem: fileSystem
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
