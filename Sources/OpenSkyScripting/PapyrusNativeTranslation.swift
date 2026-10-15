// `TranslateTo`, `SplineTranslateTo`, and `StopTranslation`
// (<https://ck.uesp.net/wiki/TranslateTo_-_ObjectReference>). Angles are degrees and the
// rotation cap degrees per second, as the wiki states. See docs/engine/papyrus-translation.md.

import Foundation
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusNativeFunctions {
    public static func installTranslation(into registry: inout PapyrusNativeRegistry) {
        // `SplineTranslateTo` puts a tangent magnitude before the speed. OpenSky moves in a
        // straight line, so the tangent is read past and not used.
        for (name, speedIndex) in [("TranslateTo", 6), ("SplineTranslateTo", 7)] {
            scriptState("ObjectReference", name, into: &registry) { call, bridge, key in
                guard let request = translationRequest(call, speedIndex: speedIndex) else {
                    return failure(call, "\(name) needs finite numbers")
                }
                guard
                    bridge.startTranslation(
                        of: key, to: request.target,
                        speed: request.speed, maxRotationSpeed: request.maxRotationSpeed
                    )
                else { return needsResidentReference(call) }
                return .returned(.none)
            }
        }
        scriptState("ObjectReference", "StopTranslation", into: &registry) { _, bridge, key in
            bridge.stopTranslation(of: key)
            return .returned(.none)
        }
    }

    private static func translationRequest(
        _ call: PapyrusNativeCall, speedIndex: Int
    ) -> TranslationRequest? {
        var values: [Float] = []
        for index in 0 ... speedIndex {
            guard let value = float(call, at: index), value.isFinite else { return nil }
            values.append(value)
        }
        let capIndex = speedIndex + 1
        let capDegrees = call.arguments.indices.contains(capIndex) ? float(call, at: capIndex) : 0
        guard let capDegrees, capDegrees.isFinite else { return nil }
        let radians = Float.pi / 180
        let target = ReferenceTransformOverride(
            position: SIMD3(values[0], values[1], values[2]),
            rotation: SIMD3(values[3], values[4], values[5]) * radians
        )
        return TranslationRequest(
            target: target, speed: values[speedIndex], maxRotationSpeed: capDegrees * radians
        )
    }
}

private struct TranslationRequest {
    let target: ReferenceTransformOverride
    let speed: Float
    let maxRotationSpeed: Float
}
