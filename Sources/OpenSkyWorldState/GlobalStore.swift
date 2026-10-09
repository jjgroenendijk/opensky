// GLOB records and the global-value lookup. `GlobalStore` holds the plugin
// defaults and is built once. `GlobalResolution` adds the session overrides and
// answers "what is this global worth now?" (docs/engine/global-variables.md).

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// The GLOB records in one plugin. Editor-ID lookup ignores case, because
/// scripts and the console name globals that way.
nonisolated public final class GlobalStore: Sendable {
    private let globalsByFormID: [UInt32: Global]
    /// Keys are lowercased.
    private let formIDsByEditorID: [String: UInt32]
    /// Resolved through the master list, so overrides and saves never key off a
    /// load-order-relative number.
    private let keysByFormID: [UInt32: ReferenceKey]
    public let skippedRecords: SkippedRecords

    public static let empty = GlobalStore(globals: [], resolver: FormIDResolver(
        pluginName: "", masters: []
    ))

    /// `pluginName` is needed because a plugin does not store its own name.
    public convenience init(file: ESMFile, pluginName: String) {
        self.init(loadOrder: LoadOrderPlugins(file: file, name: pluginName))
    }

    /// Every plugin's GLOB records; a later plugin's default value wins.
    public convenience init(loadOrder: LoadOrderPlugins) {
        var skipped = SkippedRecords()
        let decoded = loadOrder.decodeRecords(of: "GLOB", skipped: &skipped) {
            try Global(record: $0)
        }
        self.init(globals: decoded, resolver: loadOrder.space, skippedRecords: skipped)
    }

    public init(
        globals: [Global],
        resolver: FormIDResolver,
        skippedRecords: SkippedRecords = SkippedRecords()
    ) {
        self.skippedRecords = skippedRecords
        var byFormID: [UInt32: Global] = [:]
        var byEditorID: [String: UInt32] = [:]
        var keys: [UInt32: ReferenceKey] = [:]
        byFormID.reserveCapacity(globals.count)
        for global in globals {
            byFormID[global.formID.rawValue] = global
            if let editorID = global.editorID, !editorID.isEmpty {
                byEditorID[editorID.lowercased()] = global.formID.rawValue
            }
            if let key = ReferenceKey.resolve(global.formID, using: resolver) {
                keys[global.formID.rawValue] = key
            }
        }
        globalsByFormID = byFormID
        formIDsByEditorID = byEditorID
        keysByFormID = keys
    }

    public var count: Int {
        globalsByFormID.count
    }

    public var isEmpty: Bool {
        globalsByFormID.isEmpty
    }

    public func global(_ id: FormID) -> Global? {
        globalsByFormID[id.rawValue]
    }

    public func global(editorID: String) -> Global? {
        guard let raw = formIDsByEditorID[editorID.lowercased()] else { return nil }
        return globalsByFormID[raw]
    }

    public func formID(editorID: String) -> FormID? {
        formIDsByEditorID[editorID.lowercased()].map(FormID.init(stored:))
    }

    /// The key overrides and saves use. Nil for a FormID this plugin does not define.
    public func key(for id: FormID) -> ReferenceKey? {
        keysByFormID[id.rawValue]
    }

    public func key(editorID: String) -> ReferenceKey? {
        guard let raw = formIDsByEditorID[editorID.lowercased()] else { return nil }
        return keysByFormID[raw]
    }

    /// Editor-ID order; a record without one sorts by its FormID spelling.
    public func sortedGlobals() -> [Global] {
        globalsByFormID.values.sorted {
            ($0.editorID ?? $0.formID.description) < ($1.editorID ?? $1.formID.description)
        }
    }
}

/// The one place anything asks for a global's current value: the game clock
/// for time globals, then a session override, then the plugin default. Nil
/// means no known global. It works from a snapshot off the main actor too.
nonisolated public struct GlobalResolution: Sendable {
    private let defaults: GlobalStore
    private let overrides: [ReferenceKey: GlobalValue]
    /// Answers the five time globals (`GameHour` and the rest) before any
    /// override. Captured at init. `TimeScale` stays an ordinary global.
    private let clock: GameClock?

    public static let empty = GlobalResolution(defaults: .empty, overrides: [:])

    public init(
        defaults: GlobalStore?,
        overrides: [ReferenceKey: GlobalValue] = [:],
        clock: GameClock? = nil
    ) {
        self.defaults = defaults ?? .empty
        self.overrides = overrides
        self.clock = clock
    }

    /// Resolution over a snapshot's globals, for a consumer running off the
    /// main actor where the live store is unreachable.
    public init(defaults: GlobalStore?, snapshot: WorldStateSnapshot, clock: GameClock? = nil) {
        var overrides: [ReferenceKey: GlobalValue] = [:]
        overrides.reserveCapacity(snapshot.globals.count)
        for entry in snapshot.globals {
            overrides[entry.key] = entry.value
        }
        self.init(defaults: defaults, overrides: overrides, clock: clock)
    }

    /// Current value of the global `id` names, or nil when no global does.
    public func value(for id: FormID) -> GlobalValue? {
        guard let global = defaults.global(id) else { return nil }
        if
            let clock, let editorID = global.editorID,
            let timeGlobal = GameClock.TimeGlobal(editorID: editorID)
        {
            return GlobalValue(
                type: global.valueType,
                rawValue: clock.projectedValue(timeGlobal)
            )
        }
        guard let key = defaults.key(for: id), let override = overrides[key] else {
            return global.defaultValue
        }
        return override
    }

    public func value(editorID: String) -> GlobalValue? {
        guard let id = defaults.formID(editorID: editorID) else { return nil }
        return value(for: id)
    }

    /// The value as a `Float`, whatever the declared type.
    public func floatValue(for id: FormID) -> Float? {
        value(for: id)?.value
    }

    public func floatValue(editorID: String) -> Float? {
        value(editorID: editorID)?.value
    }

    /// Right-hand side of a CTDA comparison. Nil means an undefined global: the
    /// condition cannot be evaluated, which is not the same as comparing to 0.
    public func comparisonValue(_ comparison: Condition.ComparisonValue) -> Float? {
        switch comparison {
        case let .value(literal): literal
        case let .global(id): floatValue(for: id)
        }
    }

    /// True when the session has recorded an override for `id`.
    public func isOverridden(_ id: FormID) -> Bool {
        guard let key = defaults.key(for: id) else { return false }
        return overrides[key] != nil
    }
}
