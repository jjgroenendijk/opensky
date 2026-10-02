// Text lines for any decoded record value, walked by reflection. It lets the
// record dump show every decoded field of every record type. A FormID goes
// through the caller's resolver, so links read as editor IDs.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public enum DecodedValueDump {
    public typealias Resolve = (FormID) -> String

    /// Elements printed per collection before the rest is summarized.
    public static let collectionCap = 24
    public static let lineCap = 400
    private static let depthCap = 8

    public static func lines(_ value: Any, resolve: Resolve) -> [String] {
        var lines: [String] = []
        append(value, label: nil, depth: 0, resolve: resolve, into: &lines)
        if lines.count > lineCap {
            let dropped = lines.count - lineCap
            lines = Array(lines.prefix(lineCap)) + ["[INFO] \(dropped) more lines not shown"]
        }
        return lines
    }

    /// The decoded fields of `record`, or a warning line when its decoder throws.
    public static func lines(record: ESMRecord, localized: Bool, resolve: Resolve) -> [String] {
        guard RecordDecoders.decoder(for: record.type) != nil else {
            return ["[WARNING] no decoder for \(record.type)"]
        }
        do {
            let value = try RecordDecoders.decode(record, localized: localized)
            return ["decoded fields:"] + lines(value, resolve: resolve)
        } catch {
            return ["[WARNING] \(record.type) decode failed: \(error)"]
        }
    }

    private static func append(
        _ value: Any,
        label: String?,
        depth: Int,
        resolve: Resolve,
        into lines: inout [String]
    ) {
        let indent = String(repeating: "  ", count: depth + 1)
        let prefix = label.map { "\(indent)\($0): " } ?? indent
        guard let value = unwrapped(value) else {
            lines.append(prefix + "nil")
            return
        }
        if let leaf = leafText(value, resolve: resolve) {
            lines.append(prefix + leaf)
            return
        }
        let mirror = Mirror(reflecting: value)
        guard depth < depthCap else {
            lines.append(prefix + String(describing: value))
            return
        }
        switch mirror.displayStyle {
        case .collection, .set, .dictionary:
            lines.append(prefix + "\(mirror.children.count) entries")
            for (index, child) in mirror.children.prefix(collectionCap).enumerated() {
                append(
                    child.value,
                    label: "[\(index)]",
                    depth: depth + 1,
                    resolve: resolve,
                    into: &lines
                )
            }
            if mirror.children.count > collectionCap {
                lines.append(indent + "  \(mirror.children.count - collectionCap) more")
            }
        default:
            if let label {
                lines.append(indent + label + ":")
            }
            let childDepth = label == nil ? depth : depth + 1
            for child in mirror.children {
                append(
                    child.value,
                    label: child.label,
                    depth: childDepth,
                    resolve: resolve,
                    into: &lines
                )
            }
        }
    }

    /// The value inside any number of optionals, or nil for an empty one.
    private static func unwrapped(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        guard let wrapped = mirror.children.first else { return nil }
        return unwrapped(wrapped.value)
    }

    /// One-line text for a value with no useful inner structure, or nil.
    private static func leafText(_ value: Any, resolve: Resolve) -> String? {
        if let formID = value as? FormID {
            return resolve(formID)
        }
        if let data = value as? Data {
            return "\(data.count) bytes"
        }
        if let string = value as? String {
            return "\"\(string)\""
        }
        if
            Mirror(reflecting: value).children
                .isEmpty || value is FourCC || value is LString || isSIMD(value)
        {
            return String(describing: value)
        }
        return nil
    }

    private static func isSIMD(_ value: Any) -> Bool {
        String(describing: type(of: value)).hasPrefix("SIMD")
    }
}
