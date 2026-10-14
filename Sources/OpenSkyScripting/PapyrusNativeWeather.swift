// `Weather` natives (<https://ck.uesp.net/wiki/Weather_Script>) over the session's
// `PapyrusWeatherControlling` port. A session without a sky fails them with a reason.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    public static func installWeather(into registry: inout PapyrusNativeRegistry) {
        // `SetActive(bool abOverride = false, bool abAccelerate = false)` blends, and
        // `ForceActive(bool abOverride = false)` snaps. An override holds the weather.
        for (name, instant) in [("SetActive", false), ("ForceActive", true)] {
            weather(name, into: &registry) { call, sky, key, _ in
                guard let key else { return failure(call, "\(name) needs a weather") }
                let held = boolean(call, at: 0, default: false)
                guard sky.setWeather(key, held: held, instant: instant) else {
                    return failure(call, "\(name) needs a WTHR form")
                }
                return .returned(.none)
            }
        }
        weather("ReleaseOverride", into: &registry) { _, sky, _, _ in
            sky.releaseWeather()
            return .returned(.none)
        }
        weather("GetCurrentWeather", into: &registry) { _, sky, _, bridge in
            .returned(sky.currentWeather.map { handle($0, in: bridge) } ?? .none)
        }
        // `Weather FindWeather(int auiType)`: the first candidate of that classification.
        weather("FindWeather", into: &registry) { call, sky, _, bridge in
            guard let type = integer(call, at: 0) else {
                return failure(call, "FindWeather needs an int")
            }
            let match = sky.candidateWeathers().first { sky.classification(of: $0) == type }
            return .returned(match.map { handle($0, in: bridge) } ?? .none)
        }
        weather("GetClassification", into: &registry) { call, sky, key, _ in
            guard let key, let code = sky.classification(of: key) else {
                return failure(call, "GetClassification needs a WTHR form")
            }
            return .returned(.integer(code))
        }
    }

    /// Registers a `Weather` native. The receiver's key is nil for a global function.
    private static func weather(
        _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, any PapyrusWeatherControlling, ReferenceKey?,
            PapyrusWorldStateBridge
        ) -> PapyrusNativeResult
    ) {
        let native: PapyrusNativeFunction.Body = { call, context in
            guard
                let bridge = context.world as? PapyrusWorldStateBridge,
                let sky = bridge.weather
            else { return failure(call, "\(name) needs a session with weather") }
            let key = call.receiver.flatMap(bridge.referenceKey(for:))
            return body(call, sky, key, bridge)
        }
        registry.register(PapyrusNativeFunction(
            scriptName: "Weather",
            functionName: name,
            body: native
        ))
    }
}
