// A WEAP with a CNAM template takes most of its values from it (docs/formats/item-records.md).

import OpenSkyFormatsESM

nonisolated extension ItemDefinitionStore {
    /// Each weapon with a `CNAM` template takes the template's values, after the template
    /// took its own. A loop in the chain, or a missing template, leaves a weapon as it is.
    static func inheritingTemplates(_ weapons: [UInt32: Weapon]) -> [UInt32: Weapon] {
        var resolved: [UInt32: Weapon] = [:]
        func resolve(_ id: UInt32, visiting: Set<UInt32>) -> Weapon? {
            if let done = resolved[id] {
                return done
            }
            guard let weapon = weapons[id] else { return nil }
            guard
                let template = weapon.template?.rawValue, !visiting.contains(template),
                let base = resolve(template, visiting: visiting.union([id]))
            else {
                resolved[id] = weapon
                return weapon
            }
            let merged = weapon.inheriting(from: base)
            resolved[id] = merged
            return merged
        }
        for id in weapons.keys.sorted() {
            _ = resolve(id, visiting: [])
        }
        return resolved
    }
}
