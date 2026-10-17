// One readout line of the decoded fields that set keys, soul gems, and apparatus
// apart, for the inventory panels. See docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsESM

nonisolated extension ItemDefinitionStore {
    /// For example `Filled with Petty Soul, capacity Grand`. Nil for every other family.
    public func familyDetail(_ id: FormID, souls: SoulTexts = .vanilla) -> String? {
        switch definition(id)?.family {
        case .key:
            return "key"
        case .soulGem:
            guard let gem = soulGems[id.rawValue] else { return nil }
            let capacity = gem.capacity.map(souls.name(of:)) ?? "none"
            return "\(souls.contents(gem.containedSoul)), capacity \(capacity)"
        case .apparatus:
            return apparatus[id.rawValue]?.quality.map { "quality \($0)" }
        default:
            return nil
        }
    }
}
