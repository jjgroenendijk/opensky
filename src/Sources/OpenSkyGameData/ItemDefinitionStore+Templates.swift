// A WEAP with a CNAM template and an ARMO with a TNAM template take most of their values
// from it (docs/formats/item-records.md#weap, docs/formats/armor.md#armo-templates).

public import OpenSkyFormatsESM

nonisolated extension ItemDefinitionStore {
    /// Each weapon with a `CNAM` template takes the template's values, after the template
    /// took its own. A loop in the chain, or a missing template, leaves a weapon as it is.
    public static func inheritingTemplates(_ weapons: [UInt32: Weapon]) -> [UInt32: Weapon] {
        inheriting(weapons, template: \.template) { $0.inheriting(from: $1) }
    }

    /// Each armour with a `TNAM` template takes the template's values, as weapons do.
    public static func inheritingTemplates(_ armors: [UInt32: Armor]) -> [UInt32: Armor] {
        inheriting(armors, template: \.details.template) { $0.inheriting(from: $1) }
    }

    private static func inheriting<Record>(
        _ records: [UInt32: Record],
        template: (Record) -> FormID?,
        merge: (Record, Record) -> Record
    ) -> [UInt32: Record] {
        var resolved: [UInt32: Record] = [:]
        func resolve(_ id: UInt32, visiting: Set<UInt32>) -> Record? {
            if let done = resolved[id] {
                return done
            }
            guard let record = records[id] else { return nil }
            guard
                let link = template(record)?.rawValue, !visiting.contains(link),
                let base = resolve(link, visiting: visiting.union([id]))
            else {
                resolved[id] = record
                return record
            }
            let merged = merge(record, base)
            resolved[id] = merged
            return merged
        }
        for id in records.keys.sorted() {
            _ = resolve(id, visiting: [])
        }
        return resolved
    }
}

nonisolated extension ItemDefinitionStore {
    /// The item views of templated weapons and armour, rebuilt from the merged records,
    /// because each view was first decoded from its own record alone.
    func applyTemplatedViews(ownWeapons: [UInt32: Weapon], strings: LocalizedStrings?) {
        for (id, weapon) in weapons where weapon.template != nil && ownWeapons[id] != nil {
            replaceView(id, ItemDefinitionViews.view(weapon, enchantments), strings: strings)
        }
        for (id, armor) in armor where armor.details.template != nil {
            replaceView(id, ItemDefinitionViews.view(armor, enchantments), strings: strings)
        }
    }

    private func replaceView(
        _ id: UInt32, _ view: ItemDefinition, strings: LocalizedStrings?
    ) {
        guard definitions[id] != nil else { return }
        definitions[id] = strings.map { view.resolvingName(with: $0) } ?? view
    }
}
