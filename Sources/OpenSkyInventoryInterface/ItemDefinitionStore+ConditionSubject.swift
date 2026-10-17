// An item as the subject of a perk's weapon or item condition tab, such as
// `HasKeyword WeapTypeMace` on the swung weapon.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension ItemDefinitionStore {
    /// Nil when the store has no load-order resolver, which leaves the tab unbound.
    public func conditionSubject(of item: FormID?) -> ConditionFormSubject? {
        guard
            let item,
            let resolver = enchantments,
            let id = resolver.store.resolvedID(item, fromPlugin: resolver.pluginName)
        else { return nil }
        return ConditionFormSubject(id: id)
    }
}
