// `Game.IncrementStat` and `Game.QueryStat`: the misc stats the journal's Stats
// page lists (<https://ck.uesp.net/wiki/IncrementStat_-_Game>).

import Foundation
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    public static func installStats(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Game",
            functionName: "IncrementStat"
        ) { call, context in
            guard let world = context.world, let name = string(call, at: 0) else {
                return failure(call, "IncrementStat needs a world runtime and a stat name")
            }
            let amount = integer(call, at: 1) ?? 1
            guard world.incrementStat(name, by: amount) else {
                return failure(call, "IncrementStat: no misc stat named \(name)")
            }
            return .returned(.none)
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "Game",
            functionName: "QueryStat"
        ) { call, context in
            guard let world = context.world, let name = string(call, at: 0) else {
                return failure(call, "QueryStat needs a world runtime and a stat name")
            }
            return .returned(.integer(world.queryStat(name)))
        })
    }
}
