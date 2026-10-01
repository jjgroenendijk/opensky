import Foundation
import OpenSkyFormatsSWF

/// Reads and writes the `EntriesA` row array that a vanilla list clip draws from.
/// Every step degrades: a missing list or a malformed row is skipped, never thrown.
nonisolated enum MenuMovieEntryList {
    static let arrayName = "EntriesA"

    /// Replaces the `EntriesA` of the list at `path` with `rows`.
    static func publish(
        _ rows: [[String: AS2Value]],
        atPath path: String,
        runtime: SWFMovieRuntime
    ) {
        guard let list = runtime.node(atPath: path, from: runtime.root) else { return }
        let entries = runtime.runtime.makeArray(
            rows.map { .object(makeRow($0, runtime: runtime)) }
        )
        list.object.assign(.object(entries), for: arrayName)
    }

    /// Row `text` values in numeric row order. The rows are numeric property
    /// names, and lexical order would put row 10 before row 2.
    static func labels(atPath path: String, runtime: SWFMovieRuntime) -> [String] {
        guard
            let list = runtime.node(atPath: path, from: runtime.root),
            let entries = list.object.lookup(arrayName)?.property.value.objectValue
        else {
            return []
        }
        return entries.ownPropertyNames
            .compactMap { name in Int(name).map { ($0, name) } }
            .sorted { $0.0 < $1.0 }
            .compactMap { _, name in
                guard
                    let row = entries.lookup(name)?.property.value.objectValue,
                    case let .string(text) = row.lookup("text")?.property.value
                else {
                    return nil
                }
                return text
            }
    }

    /// Fields go in sorted order, so two publishes of equal rows build
    /// identical objects and a published list stays comparable.
    private static func makeRow(
        _ fields: [String: AS2Value],
        runtime: SWFMovieRuntime
    ) -> AS2Object {
        let row = runtime.runtime.makeObject()
        for name in fields.keys.sorted() {
            row.assign(fields[name] ?? .undefined, for: name)
        }
        return row
    }
}

nonisolated extension MenuInputEvent {
    /// The key code and ASCII value a vanilla menu movie expects, or nil for a pointer.
    var swfKey: (code: Int, ascii: Int)? {
        switch self {
        case .move(.up): (SWFKeyCode.up, 0)
        case .move(.down): (SWFKeyCode.down, 0)
        case .move(.left): (SWFKeyCode.left, 0)
        case .move(.right): (SWFKeyCode.right, 0)
        case .button(.accept): (SWFKeyCode.enter, 13)
        case .button(.cancel): (SWFKeyCode.escape, 0)
        case .pointer: nil
        }
    }
}
