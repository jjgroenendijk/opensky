// How a cursor over a tagfile value finds the member a packfile decoder asks
// for. A decoder names a member by its path (`m_controlData.m_tau`,
// `hkaBone::m_name`, `m_gains[2]`); a tagfile writes the same names without
// `m_`. See docs/formats/hkt-tagfile.md, "Reading tagfile objects".

import Foundation

nonisolated extension HKXObjectCursor {
    struct TagStep: Equatable {
        let name: String
        let index: Int?
    }

    /// The value `field` names. An element cursor's decoder prefixes the array's
    /// own member, so a path that does not resolve is retried without its head.
    func tagged(_ field: HKXField) -> HKTValue? {
        guard let tagValue else { return nil }
        if field.name == HKXField.element.name {
            return tagValue
        }
        let path = Self.tagPath(field.name)
        for start in path.indices {
            if let value = Self.resolve(path[start...], in: tagValue) {
                return value
            }
        }
        // A packed vector, such as an `hkQsTransform`, is read by float offset.
        if
            case let .vector(floats) = tagValue, field.offset % 4 == 0,
            floats.indices.contains(field.offset / 4)
        {
            return .vector(Array(floats[(field.offset / 4)...]))
        }
        return nil
    }

    /// Little-endian bytes of the value, as a packfile would hold them. An absent
    /// member reads as zero, which is what Havok writes for a default.
    func tagBytes(at field: HKXField, size: Int) -> Data {
        var bytes = Data()
        switch tagged(field) {
        case let .real(value):
            withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
        case let .vector(floats):
            for value in floats {
                withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
            }
        case let value?:
            if let number = Self.integer(value) {
                withUnsafeBytes(of: number.littleEndian) { bytes.append(contentsOf: $0) }
            }
        case nil:
            break
        }
        if bytes.count < size {
            bytes.append(Data(count: size - bytes.count))
        }
        return bytes.prefix(size)
    }

    func tagPointer(at field: HKXField) -> HKXPointerTarget? {
        guard case let .reference(reference)? = tagged(field) else { return nil }
        return graph.tagTarget(reference)
    }

    /// The elements of an array member; an absent array is empty.
    func tagArray(at field: HKXField) -> [HKTValue] {
        switch tagged(field) {
        case let .array(values): values
        case let .vector(floats): floats.map(HKTValue.real)
        default: []
        }
    }

    static func integer(_ value: HKTValue) -> Int64? {
        switch value {
        case let .byte(byte): Int64(byte)
        case let .int(number): number
        default: nil
        }
    }

    /// `hkaBone::m_name` -> `name`; `m_gains[2]` -> `gains` at index 2.
    static func tagPath(_ name: String) -> [TagStep] {
        name.split(separator: ".").map { component in
            var text = Substring(component)
            if let scope = text.range(of: "::", options: .backwards) {
                text = text[scope.upperBound...]
            }
            var index: Int?
            if text.hasSuffix("]"), let open = text.lastIndex(of: "[") {
                index = Int(text[text.index(after: open) ..< text.index(before: text.endIndex)])
                text = text[..<open]
            }
            if text.hasPrefix("m_") {
                text = text.dropFirst(2)
            }
            return TagStep(name: String(text), index: index)
        }
    }

    static func resolve(_ path: ArraySlice<TagStep>, in value: HKTValue) -> HKTValue? {
        var current = value
        for step in path {
            guard case let .structure(fields) = current, let next = fields[step.name] else {
                return nil
            }
            current = next
            if let index = step.index {
                switch current {
                case let .array(values) where values.indices.contains(index):
                    current = values[index]
                case let .vector(floats) where floats.indices.contains(index):
                    current = .real(floats[index])
                default:
                    return nil
                }
            }
        }
        return current
    }
}
