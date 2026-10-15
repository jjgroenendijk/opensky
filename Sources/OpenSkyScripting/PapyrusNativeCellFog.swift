// `Cell.SetFogColor`, `SetFogPlanes`, and `SetFogPower` (<https://ck.uesp.net/wiki/Cell_Script>):
// they change the fog of a loaded interior. The argument names are read from the install's
// `Cell.pex`. A cell that is not the loaded interior does not change, as in the game.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

/// One script change to an interior's fog. Colours are 0...1.
public enum PapyrusFogChange: Equatable, Sendable {
    case colours(near: SIMD3<Float>, far: SIMD3<Float>)
    case planes(near: Float, far: Float)
    case power(Float)
}

extension PapyrusNativeFunctions {
    static func installCellFog(into registry: inout PapyrusNativeRegistry) {
        cellFog("SetFogColor", into: &registry) { call in
            let channels = (0 ..< 6).compactMap { integer(call, at: $0) }
            guard channels.count == 6 else { return nil }
            let colour = channels.map { Float(min(max($0, 0), 255)) / 255 }
            return .colours(
                near: SIMD3(colour[0], colour[1], colour[2]),
                far: SIMD3(colour[3], colour[4], colour[5])
            )
        }
        cellFog("SetFogPlanes", into: &registry) { call in
            guard
                let near = float(call, at: 0), let far = float(call, at: 1),
                near.isFinite, far.isFinite
            else { return nil }
            return .planes(near: near, far: far)
        }
        cellFog("SetFogPower", into: &registry) { call in
            guard let power = float(call, at: 0), power.isFinite else { return nil }
            return .power(power)
        }
    }

    private static func cellFog(
        _ name: String,
        into registry: inout PapyrusNativeRegistry,
        change: @escaping @MainActor (PapyrusNativeCall) -> PapyrusFogChange?
    ) {
        scriptState("Cell", name, into: &registry) { call, bridge, key in
            guard let apply = bridge.cellFog, let word = bridge.loadOrderWord(of: key) else {
                return failure(call, "\(name) needs the renderer and a cell")
            }
            guard let fog = change(call) else {
                return failure(call, "\(name) needs finite numbers")
            }
            _ = apply(FormID(word), fog)
            return .returned(.none)
        }
    }
}
