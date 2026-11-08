public import OpenSkyAudio
public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `WorldAudioSoundDirector`.
public protocol WorldAudioSoundDirectorPort: AnyObject {
    func actorLoopNames(of actor: ReferenceKey) -> [String]
    func fadeOutScriptSound(_ id: Int32, seconds: Float)
    func forcePlaySound(formID: FormID, position: SIMD3<Float>)
    func handleAmbienceContext(_ context: AmbienceContext)
    func handleInteraction(_ event: InteractionEvent)
    func handleInteractionAnimation(_ event: InteractionAnimationEvent)
    func isScriptSoundPlaying(_ id: Int32) -> Bool
    @discardableResult func playAnimationSound(
        editorID: String,
        source: ReferenceKey,
        at position: SIMD3<Float>
    ) -> Bool
    func playScriptSound(formID: FormID, at position: SIMD3<Float>, waitToken: UInt64?) -> Int32
    @discardableResult func playSound(
        formID: FormID,
        source: ReferenceKey,
        at position: SIMD3<Float>
    ) -> Bool
    func releaseAnimationSound(editorID: String, source: ReferenceKey)
    func retireScriptSounds() -> [UInt64: Bool]
    func setScriptSoundVolume(_ id: Int32, _ volume: Float)
    func stopAnimationSound(editorID: String, source: ReferenceKey)
    func stopScriptSound(_ id: Int32)
    func stopSound(formID: FormID, source: ReferenceKey)
}

/// The default arguments a protocol requirement cannot carry.
extension WorldAudioSoundDirectorPort {
    @discardableResult public func playScriptSound(
        formID: FormID,
        at position: SIMD3<Float>
    ) -> Int32 {
        playScriptSound(formID: formID, at: position, waitToken: nil)
    }
}
