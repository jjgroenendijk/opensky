// Decodes a record of a later plugin straight into the load order. Inside the
// scope every FormID a decoder reads moves into the load-order space, and every
// string-table ID remembers its plugin. So no decoder needs its own renumbering.
// Rules: docs/formats/formid.md#load-order-space.

import Foundation
import Synchronization

nonisolated public enum RecordDecodeScope {
    /// Maps a stored FormID value into the scope's FormID space.
    public typealias Translate = @Sendable (UInt32) -> UInt32

    private struct Context: Sendable {
        let translate: Translate?
        let stringPlugin: String?
    }

    @TaskLocal private static var context: Context?
    /// Open scopes on any task. Zero keeps `FormID.init` to one atomic load.
    private static let openScopes = Atomic<Int>(0)

    /// Runs `body` with FormIDs read through `translate` and table IDs tagged
    /// with `stringPlugin`. Nil for either leaves that part as written.
    public static func decoding<Value>(
        translate: Translate?,
        stringPlugin: String?,
        _ body: () throws -> Value
    ) rethrows -> Value {
        guard translate != nil || stringPlugin != nil else { return try body() }
        openScopes.add(1, ordering: .relaxed)
        defer { openScopes.subtract(1, ordering: .relaxed) }
        return try $context.withValue(
            Context(translate: translate, stringPlugin: stringPlugin)
        ) {
            try body()
        }
    }

    static func translated(_ raw: UInt32) -> UInt32 {
        guard
            raw != 0, openScopes.load(ordering: .relaxed) != 0,
            let translate = context?.translate
        else { return raw }
        return translate(raw)
    }

    static var stringPlugin: String? {
        guard openScopes.load(ordering: .relaxed) != 0 else { return nil }
        return context?.stringPlugin
    }
}
