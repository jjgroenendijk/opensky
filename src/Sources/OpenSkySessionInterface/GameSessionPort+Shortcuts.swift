// Shortcuts from the session port to the members of its parts, so a caller reads
// `session.playerSeat` and does not depend on which part holds it.

public import OpenSkyAudio
public import OpenSkyPhysics
public import OpenSkyRenderCore
public import OpenSkyWorldInterface
public import simd

extension GameSessionPort {
    public var footstepDirector: Audio.WorldAudioFootstepDirector? {
        get { audio.footstepDirector }
        set { audio.footstepDirector = newValue }
    }

    public var lastAudioUpdateMS: Double {
        get { audio.lastAudioUpdateMS }
        set { audio.lastAudioUpdateMS = newValue }
    }

    public var soundMixInputs: (() -> SoundMixInputs)? {
        get { audio.soundMixInputs }
        set { audio.soundMixInputs = newValue }
    }

    public var soundRumble: ((SoundRumble) -> Void)? {
        get { audio.soundRumble }
        set { audio.soundRumble = newValue }
    }

    public var celestialSky: CelestialSky? {
        sky.celestialSky
    }

    public var currentResolvedWeather: ResolvedWeather? {
        sky.currentResolvedWeather
    }

    public var interiorFogOverride: InteriorFogOverride? {
        get { sky.interiorFogOverride }
        set { sky.interiorFogOverride = newValue }
    }

    public var scriptParticles: ScriptParticleGeometry {
        get { sky.scriptParticles }
        set { sky.scriptParticles = newValue }
    }

    public var imageSpaceLinks: ImageSpaceLinks? {
        sky.imageSpaceLinks
    }

    public var cinematicCameraState: RendererCinematicCameraState {
        get { rigs.cinematicCameraState }
        set { rigs.cinematicCameraState = newValue }
    }

    public var firstPersonArmsEnabled: Bool {
        get { rigs.firstPersonArmsEnabled }
        set { rigs.firstPersonArmsEnabled = newValue }
    }

    public var firstPersonCamera: FirstPersonCamera {
        get { rigs.firstPersonCamera }
        set { rigs.firstPersonCamera = newValue }
    }

    public var playerFirstPersonRig: Rigs.PlayerFirstPersonRig? {
        rigs.playerFirstPersonRig
    }

    public var collisionQuery: CapsuleWorldCollider.CandidateQuery? {
        motion.collisionQuery
    }

    public var playerSeat: float4x4? {
        get { motion.playerSeat }
        set { motion.playerSeat = newValue }
    }

    public var playerWalkIgnoresStatics: Bool {
        get { motion.playerWalkIgnoresStatics }
        set { motion.playerWalkIgnoresStatics = newValue }
    }

    public var playerWalkPath: [SIMD3<Float>] {
        get { motion.playerWalkPath }
        set { motion.playerWalkPath = newValue }
    }

    public var terrainSampler: ((SIMD2<Float>) -> TerrainGroundSample?)? {
        motion.terrainSampler
    }
}
