// Extra data lists on the write side. Only the types OpenSky decodes can be written;
// a skipped type has no value to write back. See docs/formats/ess-change-forms.md#extra-data-list.

import Foundation

nonisolated extension ESSExtraDataList {
    public init(entries: [ESSExtraData]) {
        self.init(entries: entries, blockedBy: nil)
    }

    func write(into writer: inout ESSWriter) throws(ESSError) {
        guard blockedBy == nil else {
            throw .invalidValue(context: "extra data list is only partly decoded")
        }
        try writer.count(entries.count, "extra data")
        for entry in entries {
            writer.uint8(entry.type)
            try entry.write(into: &writer)
        }
    }
}

nonisolated extension ESSExtraData {
    /// Fields the reader drops are written as zero: lock flags, the lock tail, and an
    /// enchantment's charge.
    func write(into writer: inout ESSWriter) throws(ESSError) {
        switch self {
        case .worn, .wornLeft:
            break
        case let .ownership(owner):
            writer.refID(owner)
        case let .count(count):
            writer.uint16(count)
        case let .health(value), let .charge(value):
            writer.float32(value)
        case let .lock(level, key):
            writer.uint8(level)
            writer.uint8(0)
            writer.refID(key)
            writer.bytes(Data(count: 8))
        case let .enchantment(enchantment):
            writer.refID(enchantment)
            writer.uint16(0)
        case let .aliasInstances(instances):
            try writer.count(instances.count, "alias instances")
            for instance in instances {
                writer.refID(instance.quest)
                writer.uint32(instance.aliasID)
            }
        case let .other(type):
            throw .invalidValue(context: "extra data type \(type) has no value to write")
        }
    }
}
