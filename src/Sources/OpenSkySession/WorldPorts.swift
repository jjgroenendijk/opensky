// The world types and the lower modules answer their session ports.

import OpenSkyFormatsSWF
public import OpenSkyGameData
public import OpenSkyMenus
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
extension LoadPhaseRecorder: LoadPhaseRecorderPort {}
extension SteppedWallClock: SteppedWallClockPort {}
extension WorldAudioFootstepDirector: WorldAudioFootstepDirectorPort {}
extension WorldAudioSoundDirector: WorldAudioSoundDirectorPort {}
extension WorldMusicDirector: WorldMusicDirectorPort {}
extension WorldRenderControls: WorldRenderControlsPort {}
extension WorldStateStore: WorldStateStorePort {}
