// Equipment condition functions, indices from xEdit wbDefinitionsTES5.pas: 41
// GetClothingValue, 108 GetWeaponAnimType, 109 IsWeaponSkillType, 398 IsWeaponInList,
// 465 GetKeywordItemCount, 597 GetEquippedItemType, 664 GetReplacedItemType, 682
// WornHasKeyword, 706 HasBoundWeaponEquipped, 722 WornApparelHasKeywordCount.
// See docs/engine/condition-functions-world.md#equipment.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension ConditionFunctions {
    static func installEquipment(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 597, name: "GetEquippedItemType", parameter1: .integer
        ) { call in
            let source = call.parameter1?.asInt32 ?? 0
            return equipment(call) { Float($0.itemType(source: source)) }
        })
        // OpenSky keeps no record of the item an equip replaced, and its bound-weapon
        // effect summons no weapon, so both answer 0.
        for (index, name) in [
            (UInt16(664), "GetReplacedItemType"),
            (706, "HasBoundWeaponEquipped")
        ] {
            registry.register(ConditionFunction(
                index: index, name: name, parameter1: .integer
            ) { call in
                equipment(call) { _ in 0 }
            })
        }
        registry.register(ConditionFunction(index: 108, name: "GetWeaponAnimType") { call in
            equipment(call) { Float($0.rightWeapon?.animationType?.rawValue ?? 0) }
        })
        registry.register(ConditionFunction(
            index: 109, name: "IsWeaponSkillType", parameter1: .integer
        ) { call in
            let skill = call.parameter1?.asInt32
            return equipment(call) { Self.isTrue(skill != nil && $0.rightWeapon?.skill == skill) }
        })
        // The worn value of armour and clothing together.
        registry.register(ConditionFunction(index: 41, name: "GetClothingValue") { call in
            equipment(call) { facts in
                Float(facts.items.filter(\.isApparel).reduce(0) { $0 + Int($1.value) })
            }
        })
        installEquipmentKeywords(&registry)
    }

    private static func installEquipmentKeywords(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 682, name: "WornHasKeyword", parameter1: .formID
        ) { call in
            guard let keyword = call.parameter1?.asFormID else {
                return .failure(.unresolvedParameter(682))
            }
            return equipment(call) { Self.isTrue($0.apparel(with: keyword) > 0) }
        })
        registry.register(ConditionFunction(
            index: 722, name: "WornApparelHasKeywordCount", parameter1: .formID
        ) { call in
            guard let keyword = call.parameter1?.asFormID else {
                return .failure(.unresolvedParameter(722))
            }
            return equipment(call) { Float($0.apparel(with: keyword)) }
        })
        registry.register(ConditionFunction(
            index: 465, name: "GetKeywordItemCount", parameter1: .formID
        ) { call in
            guard let keyword = call.parameter1?.asFormID else {
                return .failure(.unresolvedParameter(465))
            }
            return call.referenceKey().flatMap { holder in
                guard let count = call.context.inventory.count(ofKeyword: keyword, in: holder)
                else { return .failure(.unavailableData(.inventory)) }
                return .success(Float(count))
            }
        })
        registry.register(ConditionFunction(
            index: 398, name: "IsWeaponInList", parameter1: .formID
        ) { call in
            guard
                let parameter = call.parameter1,
                let store = call.context.data.formLists,
                let plugin = call.context.data.sourcePlugin,
                let list = store.resolvedID(parameter.asFormID, fromPlugin: plugin),
                store.formList(list) != nil
            else { return .failure(.unavailableData(.formList)) }
            return equipment(call) { facts in
                let weapon = facts.rightWeapon.flatMap {
                    store.resolvedID($0.item, fromPlugin: plugin)
                }
                return Self.isTrue(weapon.map { store.contains($0, in: list) } ?? false)
            }
        })
    }

    /// One read of the run-on actor's equipment; no data is `.unavailableData(.inventory)`.
    private static func equipment(
        _ call: ConditionCall,
        read: (ActorEquipmentFacts) -> Float
    ) -> Result<Float, ConditionFailure> {
        call.referenceKey().flatMap { actor in
            guard let facts = call.context.inventory.equipment(of: actor) else {
                return .failure(.unavailableData(.inventory))
            }
            return .success(read(facts))
        }
    }
}
