// The equipment and keyword facts of the inventory condition seam.
// See docs/engine/condition-functions-world.md#equipment.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldState

extension InventoryCoordinator {
    /// Weapons, shield, and every equipped item of `key`. The hand types stay 0: the
    /// caller knows the graph's hand-type mapping and the readied spells. Nil without
    /// a holder.
    public func conditionEquipment(of key: ReferenceKey) -> ActorEquipmentFacts? {
        guard let equipment, let runtime, let holder = scriptHolder(key) else { return nil }
        let items = runtime.inventory.baselines.items
        func weapon(leftHand: Bool) -> EquippedWeaponFacts? {
            guard case let item?? = scriptEquippedWeapon(on: key, leftHand: leftHand) else {
                return nil
            }
            let record = items.weapon(item)
            return EquippedWeaponFacts(
                item: item, animationType: record?.animationType, skill: record?.skill
            )
        }
        let equipped = equipment.equipped(on: holder).map { item in
            let definition = items.definition(item)
            return EquippedItemFacts(
                item: item,
                keywords: definition?.keywords ?? [],
                isApparel: definition?.family == .armor,
                value: definition?.value ?? 0
            )
        }
        return ActorEquipmentFacts(
            rightWeapon: weapon(leftHand: false),
            leftWeapon: weapon(leftHand: true),
            hasShield: scriptEquippedShield(on: key).flatMap(\.self) != nil,
            items: equipped
        )
    }

    /// How many items of each KWDA keyword the holder carries. Nil without a holder.
    public func conditionKeywordCounts(of key: ReferenceKey) -> [FormID: Int32]? {
        guard let runtime, let holder = scriptHolder(key) else { return nil }
        let items = runtime.inventory.baselines.items
        var counts: [FormID: Int32] = [:]
        for stack in runtime.inventory.inventory(of: holder).stacks {
            for keyword in items.definition(stack.item)?.keywords ?? [] {
                counts[keyword, default: 0] += stack.count
            }
        }
        return counts
    }
}
