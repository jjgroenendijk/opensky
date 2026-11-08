// One record by editor ID or FormID across the whole load order, for tools that
// look up a single record. The last plugin that holds the record wins. Each call
// walks the plugins; many lookups should build a `LoadOrderRecordIndex` instead.

import Foundation

nonisolated extension LoadOrderPlugins {
    /// The winning record whose `EDID` matches, ignoring case.
    public func record(withEditorID editorID: String) -> LoadOrderRecord? {
        for plugin in plugins.reversed() {
            if let record = ESMWalk.record(withEditorID: editorID, in: plugin.file) {
                return LoadOrderRecord(record: record, plugin: plugin)
            }
        }
        return nil
    }

    /// The winning record with this load-order FormID.
    public func record(withFormID formID: FormID) -> LoadOrderRecord? {
        guard let resolved = space.resolve(formID) else { return nil }
        for plugin in plugins.reversed() {
            guard
                let local = plugin.translation.source.localFormID(of: resolved),
                let record = ESMWalk.record(withFormID: local.rawValue, in: plugin.file)
            else { continue }
            return LoadOrderRecord(record: record, plugin: plugin)
        }
        return nil
    }

    /// A FormID token (`0x0001A26F` or `1A26F`), else an editor ID.
    public func record(named token: String) -> LoadOrderRecord? {
        if let formID = FormID(token: token), let found = record(withFormID: formID) {
            return found
        }
        return record(withEditorID: token)
    }
}

nonisolated extension FormID {
    /// Hex digits with an optional `0x`; nil for anything else.
    public init?(token: String) {
        var hex = token.lowercased()
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        guard (1 ... 8).contains(hex.count), let value = UInt32(hex, radix: 16) else {
            return nil
        }
        self.init(value)
    }
}
