// Which `RNAM` large references the distant ring keeps: a listed static must still
// be large by `fLargeRefMinSize` (docs/engine/distant-lod.md, "Large references").

import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated struct LargeReferenceFilter {
    let statics: [UInt32: StaticObject]
    let settings: LargeReferenceSettings

    init(statics: [UInt32: StaticObject], settings: LargeReferenceSettings) {
        self.statics = statics
        self.settings = settings
    }

    /// The setting is read once per builder and kept in its caches.
    init(statics: [UInt32: StaticObject], caches: CellSceneCaches, loadOrder: LoadOrderPlugins) {
        let settings = caches.largeReferenceSettings ?? LargeReferenceSettings.resolve(
            store: GameSettingStore(plugins: loadOrder.plugins.map { ($0.name, $0.file) })
        )
        caches.largeReferenceSettings = settings
        self.init(statics: statics, settings: settings)
    }

    /// The listed references that are still large. `RNAM` is written by the editor;
    /// the game tests each static's size again when it loads, so a plugin that raises
    /// the setting drops the smaller ones.
    func kept(_ listed: Set<UInt32>, of collected: [CollectedReference]) -> Set<UInt32> {
        Set(collected.lazy.map(\.reference).filter { reference in
            guard listed.contains(reference.formID.rawValue) else { return false }
            guard let bounds = statics[reference.base.rawValue]?.bounds, !bounds.isEmpty else {
                return true
            }
            return settings.isLarge(bounds, scale: reference.scale)
        }.map(\.formID.rawValue))
    }
}
