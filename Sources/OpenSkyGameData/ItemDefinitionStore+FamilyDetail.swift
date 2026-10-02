// One readout line of the decoded fields that set keys, soul gems, and apparatus
// apart, for the inventory panels. See docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsESM

nonisolated extension ItemDefinitionStore {
    /// For example `soul petty, capacity grand`. Nil for every other family.
    public func familyDetail(_ id: FormID) -> String? {
        switch definition(id)?.family {
        case .key:
            return "key"
        case .soulGem:
            guard let gem = soulGems[id.rawValue] else { return nil }
            let soul = gem.containedSoul.map { "\($0)" } ?? "none"
            let capacity = gem.capacity.map { "\($0)" } ?? "none"
            return "soul \(soul), capacity \(capacity)"
        case .apparatus:
            return apparatus[id.rawValue]?.quality.map { "quality \($0)" }
        default:
            return nil
        }
    }
}
