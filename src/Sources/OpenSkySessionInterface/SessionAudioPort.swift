public import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// The world audio graph, the directors, and the sound mix inputs. Part of `GameSessionPort`.
public protocol SessionAudioPort: AnyObject {
    associatedtype WorldAudioSoundDirector: WorldAudioSoundDirectorPort
    associatedtype WorldAudioFootstepDirector: WorldAudioFootstepDirectorPort
    associatedtype AnimationEventCoordinator: AnimationEventPort
    var animationEvents: AnimationEventCoordinator? { get }
    var footstepDirector: WorldAudioFootstepDirector? { get set }
    var lastAudioUpdateMS: Double { get set }
    var soundDirector: WorldAudioSoundDirector? { get set }
    var soundMixInputs: (() -> SoundMixInputs)? { get set }
    var soundRumble: ((SoundRumble) -> Void)? { get set }
    var worldAudio: WorldAudioEngine? { get set }
}
