// The sun and sky natives: `Game.GetSunPositionX`, `Y`, and `Z`, `Weather.GetSkyMode`,
// `Game.IsPlayerSungazing`, and `Game.SetSunGazeImageSpaceModifier`, whose modifier plays
// when the player starts to look at the sun. See docs/engine/papyrus-world-reads.md#the-sun.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import simd

extension PapyrusNativeFunctions.SkyNatives {
    static func installSky(into registry: inout PapyrusNativeRegistry) {
        for (axis, name) in ["GetSunPositionX", "GetSunPositionY", "GetSunPositionZ"].enumerated() {
            scriptState("Game", name, into: &registry) { _, bridge, _ in
                // "The X position of the sun, or 0.0 if the sun is not up."
                guard let position = bridge.sunGaze.sunPosition()
                else { return .returned(.float(0)) }
                return .returned(.float(position[axis]))
            }
        }
        // A global function, so it has no receiver.
        registry.register(PapyrusNativeFunction(
            scriptName: "Weather", functionName: "GetSkyMode"
        ) { call, context in
            guard
                let mode = (context.world as? PapyrusWorldStateBridge)?.natives.session.skyMode
            else { return failure(call, "GetSkyMode needs the sky") }
            return .returned(.integer(mode()))
        })
        // "Checks to the see if the player is looking directly at the sun."
        scriptState("Game", "IsPlayerSungazing", into: &registry) { _, bridge, _ in
            .returned(.boolean(bridge.sunGaze.isPlayerSunGazing))
        }
        scriptState("Game", "SetSunGazeImageSpaceModifier", into: &registry) { call, bridge, _ in
            bridge.runState.sunGazeModifier = objectArgument(call, at: 0)
                .flatMap(bridge.referenceKey(for:))
            return .returned(.none)
        }
    }
}

/// Looking at the sun: the look direction within `coneDegrees` of it. No open source
/// gives the game's angle, so the cone is OpenSky's reading.
nonisolated enum PapyrusSunGaze: Sendable {
    static let coneDegrees: Float = 5

    static func isGazing(forward: SIMD3<Float>, towardSun: SIMD3<Float>) -> Bool {
        let lengths = simd_length(forward) * simd_length(towardSun)
        guard lengths > 0, lengths.isFinite else { return false }
        return simd_dot(forward, towardSun) / lengths >= cos(coneDegrees * .pi / 180)
    }
}

extension PapyrusWorldStateBridge.SunGaze {
    /// The point `PapyrusWorldStateBridge.sunDistance` from the player's eye toward the sun, or nil
    /// while it is down.
    func sunPosition() -> SIMD3<Float>? {
        guard
            let toward = bridge.natives.session.towardSun?(),
            let view = bridge.natives.session.playerView?()
        else { return nil }
        return view.eye + simd_normalize(toward) * PapyrusWorldStateBridge.sunDistance
    }

    /// Whether the player looks at the sun now.
    public var isPlayerSunGazing: Bool {
        guard
            let toward = bridge.natives.session.towardSun?(),
            let view = bridge.natives.session.playerView?()
        else { return false }
        return PapyrusSunGaze.isGazing(forward: view.forward, towardSun: toward)
    }

    /// Once a frame: plays the scripted sun-gaze modifier when the player starts to look
    /// at the sun (<https://ck.uesp.net/wiki/SetSunGazeImageSpaceModifier_-_Game>).
    public func updateSunGaze() {
        let gazing = bridge.runState.sunGazeModifier != nil && isPlayerSunGazing
        defer { bridge.runState.wasSunGazing = gazing }
        guard
            gazing, !bridge.runState.wasSunGazing,
            let modifier = bridge.runState.sunGazeModifier else { return }
        _ = bridge.ports.effectPresenter?.applyImageSpaceModifier(
            modifier, strength: 1, held: false, fadeSeconds: 0
        )
    }
}
