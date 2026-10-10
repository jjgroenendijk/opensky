// Tagfile objects behind the packfile object API, so every behaviour decoder
// reads a `.hkt` set unchanged. Objects sit in a reserved section at their index.
// Field rules: docs/formats/hkt-tagfile.md, "Reading tagfile objects".

import Foundation

nonisolated extension HKXObjectGraph {
    /// The section a tagfile object's pointer target names. No packfile has it.
    public static let tagSection = -1

    /// The graph of a packfile or a tagfile, chosen by the file's magic.
    public static func decode(_ data: Data) throws -> HKXObjectGraph {
        if isTagfile(data) {
            return try HKXObjectGraph(tagfile: HKTagfile(data: data))
        }
        return try HKXObjectGraph(file: HKXFile(data: data))
    }

    public static func isTagfile(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        let words = data.prefix(8).withUnsafeBytes { raw in
            (
                raw.loadUnaligned(fromByteOffset: 0, as: UInt32.self).littleEndian,
                raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian
            )
        }
        return words.0 == HKTagfile.magic0 && words.1 == HKTagfile.magic1
    }

    func tagObject(at target: HKXPointerTarget) -> HKTFields? {
        guard let tagfile, target.sectionIndex == Self.tagSection else { return nil }
        return tagfile.objects.indices.contains(target.dataOffset)
            ? tagfile.objects[target.dataOffset] : nil
    }

    /// `base` is the object's index, so a pointer to the object matches the cursor.
    func tagCursor(over value: HKTValue, base: Int = 0) -> HKXObjectCursor {
        HKXObjectCursor(
            graph: self, sectionIndex: Self.tagSection, base: base, payload: Data(),
            tagValue: value
        )
    }

    /// The target of a tagfile reference, or nil for null or a dangling index.
    func tagTarget(_ reference: HKTReference) -> HKXPointerTarget? {
        guard let tagfile else { return nil }
        let index: Int? = switch reference {
        case .null: nil
        case let .object(index): index
        case let .remembered(index):
            tagfile.remembered.indices.contains(index) ? tagfile.remembered[index] : nil
        }
        guard let index, tagfile.objects.indices.contains(index) else { return nil }
        return HKXPointerTarget(sectionIndex: Self.tagSection, dataOffset: index)
    }
}
