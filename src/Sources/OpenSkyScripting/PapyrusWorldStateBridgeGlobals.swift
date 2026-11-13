// Global variables: the GLOB defaults with this session's overrides.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

extension PapyrusWorldStateBridge.Globals {
    public func globalValue(for key: ReferenceKey) -> GlobalValue? {
        guard let globals = bridge.stores.globals, let id = globalFormID(for: key) else {
            return bridge.worldState.globalValue(for: key)
        }
        return bridge.worldState
            .globalResolution(defaults: globals, clock: bridge.natives.session.clockSource?())
            .value(for: id)
    }

    /// A write with no GLOB record behind it — a synthetic session, or a key
    /// the loaded plugins do not define — keeps whatever type an existing
    /// override declared and otherwise treats the value as a float, rather
    /// than inventing a `short`/`long` rounding rule the plugin never stated.
    @discardableResult
    public func setGlobal(_ raw: Float, for key: ReferenceKey) -> Bool {
        if let globals = bridge.stores.globals, let id = globalFormID(for: key) {
            return bridge.worldState.setGlobal(raw, formID: id, defaults: globals)
        }
        let type = bridge.worldState.globalValue(for: key)?.type ?? .float
        return bridge.worldState.setGlobal(raw, type: type, for: key)
    }

    func globalFormID(for key: ReferenceKey) -> FormID? {
        if let globalFormIDsByKey = bridge.stores.globalFormIDsByKey {
            return globalFormIDsByKey[key]
        }
        var map: [ReferenceKey: FormID] = [:]
        for global in bridge.stores.globals?.sortedGlobals() ?? [] {
            guard let globalKey = bridge.stores.globals?.key(for: global.formID) else { continue }
            map[globalKey] = global.formID
        }
        bridge.stores.globalFormIDsByKey = map
        return map[key]
    }
}
