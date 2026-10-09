// Moves a decoded record from its plugin's FormID space into another one, such
// as the load order. Every FormID the record holds goes through the same
// translation. Rules: docs/formats/formid.md.

import Foundation

/// A decoded record whose FormIDs can be rewritten into another FormID space.
nonisolated public protocol FormIDRenumbering {
    func renumbered(_ translate: (FormID) -> FormID) -> Self
}

nonisolated extension FormIDTranslation {
    /// True when every FormID the source writes keeps its value in the target:
    /// the source lists its masters in load order and sits right after them.
    public var isIdentity: Bool {
        let names = target.masters + [target.pluginName]
        let own = source.masters.count
        guard own < names.count else { return false }
        let wanted = source.masters + [source.pluginName]
        return zip(wanted, names).allSatisfy { $0.lowercased() == $1.lowercased() }
    }

    /// `value` in the target space. An identity translation skips the copy.
    public func renumber<Value: FormIDRenumbering>(_ value: Value) -> Value {
        isIdentity ? value : value.renumbered { self($0) }
    }
}

nonisolated extension FormID? {
    func renumbered(_ translate: (FormID) -> FormID) -> FormID? {
        map(translate)
    }
}

nonisolated extension ScriptData: FormIDRenumbering {
    /// Renumbers the object properties of the attached scripts. Fragment
    /// tails belong to quests, topics, scenes, packages, and perks, which
    /// have their own load-order stores.
    public func renumbered(_ translate: (FormID) -> FormID) -> ScriptData {
        var copy = self
        copy.scripts = scripts.map { $0.renumbered(translate) }
        return copy
    }
}

nonisolated extension AttachedScript {
    func renumbered(_ translate: (FormID) -> FormID) -> AttachedScript {
        AttachedScript(
            name: name,
            flags: flags,
            properties: properties.map { property in
                ScriptProperty(
                    name: property.name,
                    type: property.type,
                    flags: property.flags,
                    value: property.value.renumbered(translate)
                )
            }
        )
    }
}

nonisolated extension ScriptPropertyValue {
    func renumbered(_ translate: (FormID) -> FormID) -> ScriptPropertyValue {
        switch self {
        case let .object(object): .object(object.renumbered(translate))
        case let .objects(objects): .objects(objects.map { $0.renumbered(translate) })
        default: self
        }
    }
}

nonisolated extension ScriptObjectReference {
    /// An alias object names its quest, so the quest FormID moves too.
    func renumbered(_ translate: (FormID) -> FormID) -> ScriptObjectReference {
        ScriptObjectReference(formID: translate(formID), alias: alias, unused: unused)
    }
}
