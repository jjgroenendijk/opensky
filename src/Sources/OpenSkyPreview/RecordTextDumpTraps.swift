// Decoded views of the trap records: a `HAZD` hazard and a `PHZD` placed hazard.
// See docs/formats/hazards.md and docs/engine/traps.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated extension RecordTextDump {
    static func trapSummary(_ record: ESMRecord, _ localized: Bool) throws -> String? {
        switch record.type {
        case "HAZD":
            let hazard = try Hazard(record: record, localized: localized)
            guard let data = hazard.properties else {
                return "decoded HAZD: editorID \(hazard.editorID ?? "-"), no DATA"
            }
            return "decoded HAZD: editorID \(hazard.editorID ?? "-"), "
                + "spell \(data.spell?.description ?? "-"), radius \(data.radius), "
                + "lifetime \(data.lifetime), target interval \(data.targetInterval), "
                + "limit \(data.limit), player only \(data.affectsPlayerOnly)"
        case "PHZD":
            let placed = try PlacedProjectile(record: record)
            return "decoded PHZD: hazard \(placed.base), position "
                + "\(vector(placed.placement.position)), "
                + "initially disabled \(placed.isInitiallyDisabled)"
                + enableParentText(placed.enableParent)
        default:
            return nil
        }
    }

    static func lockText(_ lock: LockData?) -> String {
        guard let lock else { return "" }
        return ", lock level \(lock.level.rawValue) key \(lock.key?.description ?? "none")"
            + (lock.isLeveled ? " leveled" : "")
    }

    static func enableParentText(_ parent: EnableParent?) -> String {
        guard let parent else { return "" }
        return ", enable parent \(parent.parent)" + (parent.isOppositeOfParent ? " (opposite)" : "")
    }
}
