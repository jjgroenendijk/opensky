// The world types and the lower modules answer their session ports.

public import OpenSkyFormatsESM
import OpenSkyFormatsSWF
public import OpenSkyGameData
public import OpenSkyMenus
public import OpenSkyPhysics
import OpenSkyQuestsInterface
public import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkySessionInterface
public import OpenSkyWorld
public import OpenSkyWorldState

extension ActivationGateSeam: ActivationGateSeamPort {}
extension AudioCoordinator: AudioPort {}
extension BenchmarkTourCoordinator: BenchmarkTourPort {}
extension CameraInputState: CameraInputStatePort {}
extension CellAttachment: CellAttachmentPort {}
extension CellResetCoordinator: CellResetPort {}
extension CellStreamer: @MainActor CellStreamerPort {}
extension GameSession: GameSessionPort {}
extension SessionAudio: SessionAudioPort {}
extension SessionMotion: SessionMotionPort {}
extension SessionRigs: SessionRigsPort {}
extension SessionSky: SessionSkyPort {}
extension LoadPhaseRecorder: LoadPhaseRecorderPort {}
extension SteppedWallClock: SteppedWallClockPort {}
extension WorldAudioFootstepDirector: WorldAudioFootstepDirectorPort {
    public func handleActorGraphEvents(
        _ names: [String],
        gait: LocomotionGait,
        position: SIMD3<Float>,
        surface: (armatures: [FormID], material: FormID?)
    ) {
        handleActorGraphEvents(
            names, gait: gait, position: position, armatures: surface.armatures,
            material: surface.material
        )
    }
}

extension WorldAudioSoundDirector: WorldAudioSoundDirectorPort {}
extension WorldMusicDirector: WorldMusicDirectorPort {}
extension WorldRenderControls: WorldRenderControlsPort {}
extension WorldStateStore: WorldStateStorePort {}
