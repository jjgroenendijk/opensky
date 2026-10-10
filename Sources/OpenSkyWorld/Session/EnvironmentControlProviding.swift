// Narrow live-renderer seams consumed by the World sidebar panels and the
// frame HUD. No AppKit here on purpose: the file compiles into both the app and
// the CLI target, so a protocol added here needs no project-membership change.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering

@MainActor
public protocol ShadowControlProviding: AnyObject {
    /// Sun-shadow on/off, independent of the selected quality tier so an A/B
    /// flip does not discard the tier. Was the `H` key until it became a
    /// checkbox (no dev behaviour reachable only by an unadvertised keystroke —
    /// docs/tools/app-ui.md).
    var sunShadowsEnabled: Bool { get set }
    var shadowQuality: ShadowQuality { get set }
    var shadowDrawStats: ShadowDrawStats { get }
    var shadowUpdateMS: Double { get }
    var shadowsActive: Bool { get }
    func refocusGameView()
}

@MainActor
public protocol TerrainLODControlProviding: AnyObject {
    var terrainLODConfigurationSnapshot: TerrainLODConfigurationSnapshot { get }
    var terrainLODOverrideActive: Bool { get }
    func applyTerrainLODConfiguration(_ configuration: TerrainLODConfiguration) -> Bool
    func resetTerrainLODConfiguration()
}

@MainActor
public protocol WeatherControlProviding: AnyObject {
    var weatherEnabled: Bool { get set }
    var selectableWeatherNames: [String] { get }
    func forceWeather(named name: String?)
    func forceWeather(_ preset: WeatherPreset)
    var currentWeatherName: String? { get }
    var weatherOverrideActive: Bool { get }
    var weatherTransitionFraction: Float { get }
    var weatherTransitionsPaused: Bool { get set }
    var windState: WindState { get }
    var timeOfDay: Float { get set }
    var cloudsEnabled: Bool { get set }
    /// Drawn layers, with the reason when none draw.
    var cloudReadout: String { get }
}

nonisolated public struct AnimationControlSnapshot: Equatable, Sendable {
    public let playbackCount: Int
    public let updatedBoneCount: Int
    public let updateMS: Double

    public init(playbackCount: Int, updatedBoneCount: Int, updateMS: Double) {
        self.playbackCount = playbackCount
        self.updatedBoneCount = updatedBoneCount
        self.updateMS = updateMS
    }
}

@MainActor
public protocol AnimationControlProviding: AnyObject {
    var actorAnimationsEnabled: Bool { get set }
    var animationSnapshot: AnimationControlSnapshot { get }
}

nonisolated public struct ParticleControlSnapshot: Equatable, Sendable {
    public let systemCount: Int
    public let emitterCount: Int
    public let liveCount: Int

    public init(systemCount: Int, emitterCount: Int, liveCount: Int) {
        self.systemCount = systemCount
        self.emitterCount = emitterCount
        self.liveCount = liveCount
    }
}

@MainActor
public protocol ParticleControlProviding: AnyObject {
    var particlesEnabled: Bool { get set }
    var particlesFrozen: Bool { get set }
    var particleEmissionScale: Float { get set }
    var particleSnapshot: ParticleControlSnapshot { get }
}

@MainActor
public protocol WaterControlProviding: AnyObject {
    /// Water reads the scene depth; off gives every surface a fixed middle depth.
    var waterDepthEnabled: Bool { get set }
    /// Water surfaces in the scene: cell planes and placed water meshes.
    var waterSurfaceCount: Int { get }
}

@MainActor
public protocol TerrainShadingControlProviding: AnyObject {
    /// Terrain lighting follows the land textures' TX01 normal maps.
    var terrainNormalMapsEnabled: Bool { get set }
    /// Terrain quadrant draws in the scene.
    var terrainQuadrantCount: Int { get }
    /// Base and layer textures in those draws that have a normal map.
    var terrainNormalMapCount: Int { get }
}

@MainActor
public protocol PrecipitationControlProviding: AnyObject {
    var precipitationEnabled: Bool { get set }
    var precipitationSnapshot: PrecipitationRuntimeSnapshot { get }
    /// The `SPGD` scales in use, the fallback when the weather names none.
    var precipitationTuning: PrecipitationTuning { get }
    /// The volumetric lighting the strongest weather names now, nil when none.
    var weatherVolumetricLighting: String? { get }
}

nonisolated public struct GrassControlSnapshot: Equatable, Sendable {
    public let sceneInstances: Int
    public let drawnInstances: Int
    public let drawCalls: Int
    public let distanceCulledInstances: Int
    public let densityCulledInstances: Int
    public let frustumCulledInstances: Int
    public let budgetDroppedInstances: Int

    public init(
        sceneInstances: Int,
        drawnInstances: Int,
        drawCalls: Int,
        distanceCulledInstances: Int,
        densityCulledInstances: Int,
        frustumCulledInstances: Int,
        budgetDroppedInstances: Int
    ) {
        self.sceneInstances = sceneInstances
        self.drawnInstances = drawnInstances
        self.drawCalls = drawCalls
        self.distanceCulledInstances = distanceCulledInstances
        self.densityCulledInstances = densityCulledInstances
        self.frustumCulledInstances = frustumCulledInstances
        self.budgetDroppedInstances = budgetDroppedInstances
    }
}

@MainActor
public protocol GrassControlProviding: AnyObject {
    var grassEnabled: Bool { get set }
    var grassDensityScale: Float { get set }
    var grassDrawDistance: Float { get set }
    var grassWindScale: Float { get set }
    var grassSnapshot: GrassControlSnapshot { get }
}

/// Live camera pose, as one value so a panel and the HUD read the same frame's
/// numbers rather than each polling the parts separately.
nonisolated public struct CameraPoseSnapshot: Equatable, Sendable {
    /// World position in native Skyrim units (docs/decisions/coordinates.md).
    public let position: SIMD3<Float>
    /// Heading in radians about world +Z.
    public let yaw: Float
    /// Elevation in radians, positive looking up.
    public let pitch: Float
    /// Exterior cell the position falls in, by floor division.
    public let cell: CellCoordinate
    public let movementMode: CameraMovementMode

    /// Reported by providers with no live renderer.
    public static let unavailable = CameraPoseSnapshot(
        position: .zero, yaw: 0, pitch: 0, cell: CellCoordinate(x: 0, y: 0), movementMode: .fly
    )

    public var yawDegrees: Float {
        yaw * 180 / .pi
    }

    public var pitchDegrees: Float {
        pitch * 180 / .pi
    }

    /// Short, stable name for one camera mode, used by the pasteable pose line
    /// so a bug report says which camera produced a frame.
    public static func name(of mode: CameraMovementMode) -> String {
        switch mode {
        case .fly: "fly"
        case .walk: "walk"
        case .thirdPerson: "third person"
        }
    }

    public init(
        position: SIMD3<Float>,
        yaw: Float,
        pitch: Float,
        cell: CellCoordinate,
        movementMode: CameraMovementMode
    ) {
        self.position = position
        self.yaw = yaw
        self.pitch = pitch
        self.cell = cell
        self.movementMode = movementMode
    }
}

@MainActor
public protocol CameraControlProviding: AnyObject {
    var cameraPose: CameraPoseSnapshot { get }
    var movementConfiguration: PlayerMovementConfiguration { get }
    /// Settable so every camera mode is reachable from the sidebar. The `G`
    /// key stays as an accelerator over the same renderer state, per
    /// docs/tools/app-ui.md: no dev behaviour reachable only by an unadvertised
    /// keystroke.
    var movementMode: CameraMovementMode { get set }
    /// One-line pose summary meant to be pasted into a bug report.
    var cameraPoseDescription: String { get }
}

extension CameraControlProviding {
    public var movementConfiguration: PlayerMovementConfiguration {
        .synthetic
    }

    /// Default implementation so every consumer formats the pose identically;
    /// a conformer that overrode it would let two readouts of the same camera
    /// disagree.
    public var cameraPoseDescription: String {
        let pose = cameraPose
        return String(
            format: "camera %@ | position %.1f, %.1f, %.1f | yaw %.1f deg | "
                + "pitch %.1f deg | cell %d, %d",
            CameraPoseSnapshot.name(of: pose.movementMode),
            pose.position.x, pose.position.y, pose.position.z,
            pose.yawDegrees, pose.pitchDegrees, pose.cell.x, pose.cell.y
        )
    }
}

@MainActor
public protocol FrameStatsProviding: AnyObject {
    /// Latest closed live window; `FrameStatsSnapshot.empty` before the first
    /// one closes or with no live renderer.
    var frameStatsSnapshot: FrameStatsSnapshot { get }
}

/// Per-frame scene accounting plus the streaming and memory numbers that answer
/// "is this frame slow because of what is resident?".
nonisolated public struct SceneStatsSnapshot: Equatable, Sendable {
    public let drawCalls: Int
    public let drawnInstances: Int
    public let culledInstances: Int
    public let residentCellCount: Int
    /// Process physical footprint, or nil when the mach call fails.
    public let memoryFootprintMB: Double?

    public static let empty = SceneStatsSnapshot(
        drawCalls: 0, drawnInstances: 0, culledInstances: 0,
        residentCellCount: 0, memoryFootprintMB: nil
    )

    public init(
        drawCalls: Int,
        drawnInstances: Int,
        culledInstances: Int,
        residentCellCount: Int,
        memoryFootprintMB: Double?
    ) {
        self.drawCalls = drawCalls
        self.drawnInstances = drawnInstances
        self.culledInstances = culledInstances
        self.residentCellCount = residentCellCount
        self.memoryFootprintMB = memoryFootprintMB
    }
}

@MainActor
public protocol SceneStatsProviding: AnyObject {
    var sceneStatsSnapshot: SceneStatsSnapshot { get }
}

@MainActor
public protocol AudioControlProviding: AnyObject {
    var audioEnabled: Bool { get set }
    var audioMasterVolume: Float { get set }
    func audioVolume(for category: AudioCategory) -> Float
    func setAudioVolume(_ volume: Float, for category: AudioCategory)
    /// True while the category contributes zero gain because the user muted
    /// it. Its volume is preserved, so unmuting restores that level.
    func audioCategoryIsMuted(_ category: AudioCategory) -> Bool
    func setAudioCategoryMuted(_ muted: Bool, for category: AudioCategory)
    /// The soloed category, or nil when nothing is soloed. While it is set,
    /// every other category is silent. Mute and solo are independent: soloing
    /// a category does not unmute it.
    var soloedAudioCategory: AudioCategory? { get set }
    /// VFS paths the World > Audio picker offers (vanilla: the 269 `.xwm`
    /// music files — sound effects are `.wav` and wait on a PCM reader).
    var selectableAudioFileNames: [String] { get }
    /// Streams the picked file as a positional source placed a fixed offset in
    /// front of the camera, so panning/attenuation are audible immediately.
    /// Returns nil on success or a short failure description for the readout.
    func playAudioFile(named name: String) -> String?
    func stopAllAudioSources()
    var audioStatsSnapshot: AudioStatsSnapshot { get }
    /// Fixes the room reverb's wet level, in dB; nil follows the acoustic space.
    var reverbWetOverride: Float? { get set }
    /// The `REVB` record of the current acoustic space, nil outdoors.
    var reverbRecord: ReverbParameters? { get }
    /// How the last one-shot was routed, and why.
    var lastAudioRouting: String? { get }

    // Voice-line controls. The archives hold 75,408 `.fuz` voice
    // files, far past what a picker can list, so the picker is a filter over
    // that corpus rather than the corpus itself.

    /// Substring the voice picker narrows the corpus by. Matching is on the
    /// canonical VFS key, so a voice-type directory such as
    /// `femaleeventoned` is a useful filter on its own.
    var voiceFileFilter: String { get set }
    /// Voice paths the picker currently offers: the first
    /// `voiceFilePickerLimit` matches of `voiceFileFilter`, sorted.
    var selectableVoiceFileNames: [String] { get }
    /// How many voice files match the filter, which is usually more than the
    /// picker lists. The readout states both so a truncated list never reads
    /// as the whole match set.
    var voiceFileMatchCount: Int { get }
    /// Plays one `.fuz` line positionally in front of the camera, on the voice
    /// submix. Returns nil on success or a short failure description.
    func playVoiceFile(named name: String) -> String?
    /// The line currently playing, with its container summary. Nil when no
    /// voice line has been started this session.
    var currentVoiceDescription: String? { get }
    /// Playback clock readout for the line last started: elapsed and total
    /// seconds, or why there is no reading. Empty when none was started.
    var voicePlaybackDescription: String { get }
    /// Most recent voice failure reason; nil when the last start succeeded.
    var lastVoiceError: String? { get }
    /// Applies decoded speech curves to the selected actor. Defaults on; the panel
    /// toggle is the A/B switch.
    var lipSyncEnabled: Bool { get set }
    /// Active line, track clock and live named weights for LipSyncStatsLabel.
    var lipSyncSnapshot: LipSyncSnapshot { get }
    /// Decode/association failure for the most recent line, without preventing
    /// its audio from playing.
    var lastLipSyncError: String? { get }

    // World SFX + ambience director controls. The director lives
    // beside the audio engine; these no-op when audio is not enabled.

    /// Use-key activation plays the activator's SNDR. Off still lets ambience
    /// run; the toggles are independent.
    var sfxEnabled: Bool { get set }
    /// Per-cell ambient bed starts/stops with the center cell. Off still lets
    /// one-shot SFX run.
    var ambienceEnabled: Bool { get set }
    /// Force-stops the current ambience bed; the next cell change restarts it.
    /// Verification helper for A/B inspection.
    func stopAmbience()
    /// Most recent SFX file path the director played (or failed to play).
    var lastSFXDescription: String? { get }
    /// Most recent SFX failure reason; nil when the last trigger succeeded.
    var lastSFXError: String? { get }
    /// FormIDs of the SNDR/SOUN records in the current ambient bed, joined for
    /// the readout. "none" when the bed is empty.
    var currentAmbienceDescription: String { get }

    // Music director controls. Same lazy-construction policy: these
    // no-op (and read their defaults) until audio is enabled.

    /// MUSC playlist playback follows the streamed cell. Off fades the current
    /// track out; on restarts the selection the last context resolved.
    var musicEnabled: Bool { get set }
    /// MUSC editor ids the music picker offers, sorted. Empty without data.
    var selectableMusicTypeNames: [String] { get }
    /// Forces a crossfade to a named MUSC, bypassing the precedence chain.
    /// Returns nil on success or a short failure description for the readout.
    func forceMusicType(named name: String) -> String?
    /// Force-stops music; the next cell change resolves and starts it again.
    func stopMusic()
    /// Playlist plus playing file, joined for the readout. "none" when silent.
    var currentMusicDescription: String { get }
    /// Derived music state: "exploration", "town" or "interior".
    var currentMusicStateName: String { get }
    /// Most recent music failure reason; nil when the last start succeeded.
    var lastMusicError: String? { get }

    // Footstep director controls. Same lazy-construction policy
    // again: these read their defaults and no-op until audio is enabled.

    /// Footstep events fired by the player's behavior graph play the sound the
    /// current footstep set resolves. Off leaves the player silent underfoot
    /// without touching SFX, ambience, or music.
    var footstepsEnabled: Bool { get set }
    /// Editor ID of the FSTS the player's feet resolved to, or a reason there
    /// is none.
    var currentFootstepSetDescription: String { get }
    /// The tags the current set answers to for the gait the player is in, in
    /// record order. Empty when there is no set or the gait's list is.
    var currentFootstepTags: [String] { get }
    /// Most recent footstep the director played, as "tag: path".
    var lastFootstepDescription: String? { get }
    /// Most recent footstep failure reason; nil when the last one succeeded.
    var lastFootstepError: String? { get }
    /// Events routed and footsteps played since the director was built.
    var footstepCounts: (routed: Int, played: Int) { get }
    /// The MATT footsteps currently resolve against: what the
    /// ground contact reports, or the pinned material and that it is pinned.
    var currentFootstepMaterialDescription: String { get }
    /// Every MATT the load order carries, by FormID and display name, for the
    /// material selector.
    var footstepMaterialOptions: [(id: FormID, name: String)] { get }
    /// A material pinned in place of the ground contact's, for hearing one
    /// surface deliberately. Nil follows the ground.
    var forcedFootstepMaterial: FormID? { get set }
    /// Forces one footstep for the named tag at the player's feet, so the
    /// chain can be verified without walking.
    func forcePlayFootstep(tag: String) -> String?
}
