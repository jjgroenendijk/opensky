// `Sound` natives the app answers: `Play`, `PlayAndWait`, `StopInstance`, and
// `SetInstanceVolume` (<https://ck.uesp.net/wiki/Sound_Script>), the
// `ShaderParticleGeometry` natives `Apply` and `Remove`, and the latent
// `Actor.PathToReference` and `Game.PlayBink`, answered the same way as `PlayAndWait`.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    static func installSound(into registry: inout PapyrusNativeRegistry) {
        // `int Play(ObjectReference akSource)`: 0 when the sound failed to play.
        scriptState("Sound", "Play", into: &registry) { call, bridge, sound in
            guard
                let source = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:)),
                let play = bridge.gameNatives.playSound
            else { return failure(call, "Play needs a source reference") }
            return .returned(.integer(play(sound, source, nil)))
        }
        // `bool PlayAndWait(ObjectReference akSource)`: latent until the sound ends.
        scriptState("Sound", "PlayAndWait", into: &registry) { call, bridge, sound in
            guard
                let source = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:)),
                let play = bridge.gameNatives.playSound
            else { return failure(call, "PlayAndWait needs a source reference") }
            let token = bridge.nextLatentWaitToken()
            guard play(sound, source, token) != 0 else {
                return .returned(.boolean(false))
            }
            return .suspended(.external(token))
        }
        gameHook("Sound", "StopInstance", into: &registry) { call, hooks in
            guard let stop = hooks.stopSound, let id = integer(call, at: 0) else { return nil }
            stop(id)
            return .returned(.none)
        }
        gameHook("Sound", "SetInstanceVolume", into: &registry) { call, hooks in
            guard
                let set = hooks.setSoundVolume, let id = integer(call, at: 0),
                let volume = float(call, at: 1)
            else { return nil }
            set(id, volume)
            return .returned(.none)
        }
        installParticleGeometry(into: &registry)
        installPathToReference(into: &registry)
        installPlayBink(into: &registry)
    }

    /// `PlayBink(string asFileName, bool abInterruptible = false, bool abMuteAudio = true,
    /// bool abMuteMusic = true, bool abLetterbox = true)`: latent until the movie ends.
    private static func installPlayBink(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Game", functionName: "PlayBink"
        ) { call, context in
            guard let bridge = context.world as? PapyrusWorldStateBridge else {
                return needsWorld(call)
            }
            guard let play = bridge.gameNatives.playBink, let name = string(call, at: 0) else {
                return failure(call, "PlayBink needs a file name and the running game")
            }
            let request = PapyrusBinkRequest(
                fileName: name,
                interruptible: boolean(call, at: 1, default: false),
                muteAudio: boolean(call, at: 2, default: true),
                muteMusic: boolean(call, at: 3, default: true),
                letterbox: boolean(call, at: 4, default: true)
            )
            let token = bridge.nextLatentWaitToken()
            return play(request, token) ? .suspended(.external(token)) : .returned(.none)
        })
    }

    /// `bool PathToReference(ObjectReference aTarget, float afWalkRunPercent)`: latent,
    /// false for a speed outside 0 to 1 (<https://ck.uesp.net/wiki/PathToReference_-_Actor>).
    private static func installPathToReference(into registry: inout PapyrusNativeRegistry) {
        scriptState("Actor", "PathToReference", into: &registry) { call, bridge, actor in
            guard
                let target = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:)),
                let path = bridge.gameNatives.pathToReference
            else { return failure(call, "PathToReference needs a target reference") }
            guard let speed = float(call, at: 1), (0 ... 1).contains(speed) else {
                return .returned(.boolean(false))
            }
            let token = bridge.nextLatentWaitToken()
            guard path(actor, target, speed, token) else { return .returned(.boolean(false)) }
            return .suspended(.external(token))
        }
    }

    /// `Apply(float afFadeInTime = 0.0)` and `Remove(float afFadeOutTime = 0.0)`.
    private static func installParticleGeometry(into registry: inout PapyrusNativeRegistry) {
        for (name, applies) in [("Apply", true), ("Remove", false)] {
            scriptState("ShaderParticleGeometry", name, into: &registry) { call, bridge, spgd in
                guard let set = bridge.gameNatives.setParticleGeometry else {
                    return failure(call, "\(name) needs the running game")
                }
                set(applies ? spgd : nil, max(0, float(call, at: 0) ?? 0))
                return .returned(.none)
            }
        }
    }
}

extension PapyrusWorldStateBridge {
    /// Above the actor graph's token range, so no two waits share a token. Sound and
    /// path waits share this range.
    static let firstLatentWaitToken: UInt64 = 1 << 60

    func nextLatentWaitToken() -> UInt64 {
        defer { latentWaitToken += 1 }
        return latentWaitToken
    }
}
