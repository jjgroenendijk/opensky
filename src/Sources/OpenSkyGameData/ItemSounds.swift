// The sound an item makes when it is picked up or put down: its own `YNAM` or `ZNAM`, else
// the Default Object for its kind (docs/formats/item-records.md#item-sounds).

import OpenSkyFormatsCore
public import OpenSkyFormatsESM

nonisolated public enum ItemSoundEvent: Sendable {
    case pickUp
    case putDown
}

/// The pickup and putdown Default Objects, `PUSG` to `PDSI`, in the load-order space.
nonisolated public struct ItemSoundDefaults: Equatable, Sendable {
    private var sounds: [String: FormID] = [:]

    public init() {}

    init(loadOrder: LoadOrderPlugins) {
        var skipped = SkippedRecords()
        let records = loadOrder.indexRecords(of: "DOBJ", skipped: &skipped) { record, _ in
            try DefaultObjects(record: record)
        }
        for objects in records.values {
            for name in Self.tags {
                guard let entry = objects.entry(tag: name) else { continue }
                sounds[name] = entry.object
            }
        }
    }

    /// The default sound of a `family` item for `event`.
    public func sound(for family: ItemDefinition.Family, _ event: ItemSoundEvent) -> FormID? {
        let kind = switch family {
        case .weapon: "W"
        case .armor: "A"
        case .book: "B"
        case .ingredient: "I"
        default: "G"
        }
        return sounds[(event == .pickUp ? "PUS" : "PDS") + kind]
    }

    private static let tags = ["G", "W", "A", "B", "I"].flatMap { ["PUS" + $0, "PDS" + $0] }
}

nonisolated extension ItemDefinitionStore {
    /// The sound `item` plays for `event`: its own, else its kind's default.
    public func sound(of item: FormID, _ event: ItemSoundEvent) -> FormID? {
        guard let definition = definitions[item.rawValue] else { return nil }
        let own = event == .pickUp ? definition.pickUpSound : definition.putDownSound
        return own ?? soundDefaults.sound(for: definition.family, event)
    }
}
