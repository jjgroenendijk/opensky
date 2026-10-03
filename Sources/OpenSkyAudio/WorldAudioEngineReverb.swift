// The engine half of output models and reverb: the room reverb on the
// environment node, and each curve-attenuated source's distance gain. A 3D
// source with a curve sits at the reference distance in its true direction, so
// the node's own attenuation stays neutral and the curve alone sets loudness.
// See docs/formats/sound-output-reverb.md.

import AVFAudio
import Foundation
import simd

extension WorldAudioEngine {
    /// Starts the crossfade toward `setting`.
    public func applyReverb(_ setting: ReverbSetting) {
        reverb.setTarget(setting)
        pushReverb()
    }

    /// Fixes the wet level for listening tests; nil returns it to the ramp.
    public func setReverbWetOverride(_ level: Float?) {
        reverb.wetOverride = level
        pushReverb()
    }

    func advanceReverb(deltaTime: Float) {
        guard reverb.advance(deltaTime) else { return }
        pushReverb()
    }

    /// Re-reads every curve source's distance, and moves a 3D one onto the
    /// reference sphere around the listener.
    func updateDistanceGains() {
        for source in sources where source.attenuation != nil {
            updateDistanceGain(of: source)
        }
    }

    func updateDistanceGain(of source: ActiveAudioSource) {
        guard let curve = source.attenuation else { return }
        let offset = source.worldPosition - listenerWorldPosition
        source.distanceGain = curve.gain(atDistance: simd_length(offset))
        if source.isPositional {
            let listener = AudioSpace.listenerPosition(fromWorld: listenerWorldPosition)
            let toward = AudioSpace.listenerDirection(fromWorld: offset)
            let length = simd_length(toward)
            let direction = length > 0 ? toward / length : SIMD3<Float>(0, 0, -1)
            let position = listener + direction * ProvisionalAttenuation.referenceDistanceMeters
            source.node.position = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        }
        applyVolume(to: source)
    }

    private func pushReverb() {
        let parameters = environment.reverbParameters
        if let room = reverb.room, room != reverb.loadedRoom {
            parameters.loadFactoryReverbPreset(room.preset)
            reverb.loadedRoom = room
        }
        parameters.enable = reverb.room != nil || reverb.wetOverride != nil
        parameters.level = reverb.appliedLevel
    }
}
