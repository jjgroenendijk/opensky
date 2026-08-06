// Deterministic Utility natives selected by vanilla call frequency.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    static func installUtility(into registry: inout PapyrusNativeRegistry) {
        installWaits(into: &registry)
        installRandom(into: &registry)
    }

    private static func installWaits(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Utility",
            functionName: "Wait"
        ) { call, _ in
            guard let seconds = float(call, at: 0), seconds.isFinite else {
                return failure(call, "Wait needs a finite duration")
            }
            return .suspended(.realSeconds(Double(max(0, seconds))))
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "Utility",
            functionName: "WaitGameTime"
        ) { call, _ in
            guard let hours = float(call, at: 0), hours.isFinite else {
                return failure(call, "WaitGameTime needs a finite duration")
            }
            return .suspended(.gameHours(Double(max(0, hours))))
        })
    }

    private static func installRandom(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Utility",
            functionName: "RandomInt"
        ) { call, context in
            guard
                let lower = integer(call, at: 0),
                let upper = integer(call, at: 1),
                lower <= upper
            else {
                return failure(call, "RandomInt needs an ordered integer range")
            }
            let width = UInt64(Int64(upper) - Int64(lower)) + 1
            let offset = Int64(context.random.next() % width)
            return .returned(.integer(Int32(Int64(lower) + offset)))
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "Utility",
            functionName: "RandomFloat"
        ) { call, context in
            guard
                let lower = float(call, at: 0),
                let upper = float(call, at: 1),
                lower.isFinite,
                upper.isFinite,
                lower <= upper
            else {
                return failure(call, "RandomFloat needs an ordered finite range")
            }
            let unit = Float(context.random.next() >> 40) / Float(1 << 24)
            return .returned(.float(lower + (upper - lower) * unit))
        })
    }
}
