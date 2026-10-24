// The app side of the `Cell` fog natives: a change reaches the renderer only when the cell
// is the loaded interior.

import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld

extension ScriptWorldAdapter {
    func changeFog(_ change: PapyrusFogChange, in cell: FormID) -> Bool {
        guard
            let renderer = game.renderer, let gameSession = game.gameSession,
            let lighting = renderer.scene.lighting,
            case let .interior(loaded)? = game.streamer?.interiorScene?.location, loaded == cell
        else { return false }
        var fog = gameSession.interiorFogOverride.flatMap { $0.base == lighting ? $0 : nil }
            ?? InteriorFogOverride(base: lighting)
        switch change {
        case let .colours(near, far): fog.setColours(near: near, far: far)
        case let .planes(near, far): fog.setPlanes(near: near, far: far)
        case let .power(power): fog.setPower(power)
        }
        gameSession.interiorFogOverride = fog
        return true
    }
}
