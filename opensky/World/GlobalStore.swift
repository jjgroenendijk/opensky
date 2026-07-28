// GLOB index and the global-value lookup seam (issue #165, roadmap item
// 10.2.2).
//
// Two layers live here and they have deliberately different lifetimes.
// `GlobalStore` is the plugin side: an immutable index built once from an
// `ESMFile`, exactly like `WeatherStore` and `SoundRecordStore`, holding only
// value types afterwards so it is safe to read from the cell-build queue.
// `GlobalResolution` is the seam every consumer asks "what is this global worth
// right now?" through: it pairs those plugin defaults with the session's
// runtime overrides from `WorldStateStore` and answers with one value.
//
// The condition evaluator (issue #251) and the game clock (issue #164) are the
// two consumers this seam exists for, and the climate weather-chance selection
// in `WeatherSelection` is the first one wired up.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// Immutable index of the GLOB records in one plugin.
///
/// Editor-ID lookup is case-insensitive. Weather and worldspace records are
/// indexed by their exact spelling elsewhere in the engine, but a global is
/// named by scripts and by the console, where Skyrim has always matched editor
/// IDs without regard to case, so this index normalizes instead.
nonisolated final class GlobalStore: Sendable {
    /// Raw FormID -> decoded record.
    private let globalsByFormID: [UInt32: Global]
    /// Lowercased editor ID -> raw FormID.
    private let formIDsByEditorID: [String: UInt32]
    /// Raw FormID -> session-stable identity, resolved once through the
    /// plugin's master list so runtime overrides and saves never key off a
    /// load-order-relative number.
    private let keysByFormID: [UInt32: ReferenceKey]

    static let empty = GlobalStore(globals: [], resolver: FormIDResolver(
        pluginName: "", masters: []
    ))

    /// - Parameter pluginName: file name of `file`, needed because a plugin
    ///   does not record its own name and `ReferenceKey` is built from it.
    convenience init(file: ESMFile, pluginName: String) {
        let masters = (try? file.pluginHeader().masters) ?? []
        var decoded: [Global] = []
        if let top = file.topGroup(of: "GLOB"), let children = try? top.children() {
            for case let .record(record) in children where record.type == "GLOB" {
                guard let global = try? Global(record: record) else { continue }
                decoded.append(global)
            }
        }
        self.init(
            globals: decoded,
            resolver: FormIDResolver(pluginName: pluginName, masters: masters)
        )
    }

    init(globals: [Global], resolver: FormIDResolver) {
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

    var count: Int {
        globalsByFormID.count
    }

    var isEmpty: Bool {
        globalsByFormID.isEmpty
    }

    func global(_ id: FormID) -> Global? {
        globalsByFormID[id.rawValue]
    }

    func global(editorID: String) -> Global? {
        guard let raw = formIDsByEditorID[editorID.lowercased()] else { return nil }
        return globalsByFormID[raw]
    }

    func formID(editorID: String) -> FormID? {
        formIDsByEditorID[editorID.lowercased()].map(FormID.init)
    }

    /// Session-stable key for a global, which is how the runtime layer and the
    /// save file address it. Nil for a FormID this plugin does not define.
    func key(for id: FormID) -> ReferenceKey? {
        keysByFormID[id.rawValue]
    }

    func key(editorID: String) -> ReferenceKey? {
        guard let raw = formIDsByEditorID[editorID.lowercased()] else { return nil }
        return keysByFormID[raw]
    }

    /// Records in editor-ID order, for inspection surfaces. Records without an
    /// editor ID sort by FormID under their hex spelling.
    func sortedGlobals() -> [Global] {
        globalsByFormID.values.sorted {
            ($0.editorID ?? $0.formID.description) < ($1.editorID ?? $1.formID.description)
        }
    }
}

/// The one place anything asks for a global's current value.
///
/// Resolution order is fixed and total: a runtime override recorded in this
/// session wins, the plugin default is the answer otherwise, and nil means the
/// FormID names no global this store knows. Consumers never reach past this
/// into `WorldStateStore`, which is what lets the value come from a snapshot on
/// a build thread just as easily as from the live store on the main actor.
nonisolated struct GlobalResolution: Sendable {
    private let defaults: GlobalStore
    private let overrides: [ReferenceKey: GlobalValue]
    /// Game clock the five vanilla time globals project from (issue #164).
    /// When set, `GameHour`/`GameDaysPassed`/`GameDay`/`GameMonth`/`GameYear`
    /// answer from the clock — before any override, so a stale override can
    /// never shadow the clock. The projection captures the clock at
    /// construction: a consumer reading time builds a fresh resolution.
    /// `TimeScale` is not projected; it stays an ordinary global.
    private let clock: GameClock?

    static let empty = GlobalResolution(defaults: .empty, overrides: [:])

    init(
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
    init(defaults: GlobalStore?, snapshot: WorldStateSnapshot, clock: GameClock? = nil) {
        var overrides: [ReferenceKey: GlobalValue] = [:]
        overrides.reserveCapacity(snapshot.globals.count)
        for entry in snapshot.globals {
            overrides[entry.key] = entry.value
        }
        self.init(defaults: defaults, overrides: overrides, clock: clock)
    }

    /// Current value of the global `id` names, or nil when no global does.
    func value(for id: FormID) -> GlobalValue? {
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

    func value(editorID: String) -> GlobalValue? {
        guard let id = defaults.formID(editorID: editorID) else { return nil }
        return value(for: id)
    }

    /// Numeric shorthand for a caller that does not care about the declared
    /// type, such as the game clock reading `TimeScale` (issue #164).
    func floatValue(for id: FormID) -> Float? {
        value(for: id)?.value
    }

    func floatValue(editorID: String) -> Float? {
        value(editorID: editorID)?.value
    }

    /// Right-hand side of a CTDA comparison (issue #251).
    ///
    /// A literal comparison value passes through unchanged; a `use global`
    /// comparison resolves through this store. Nil means the condition
    /// references a global nothing defines, which the evaluator must treat as
    /// an unevaluatable condition rather than as a comparison against zero.
    func comparisonValue(_ comparison: Condition.ComparisonValue) -> Float? {
        switch comparison {
        case let .value(literal): literal
        case let .global(id): floatValue(for: id)
        }
    }

    /// True when the session has recorded an override for `id`.
    func isOverridden(_ id: FormID) -> Bool {
        guard let key = defaults.key(for: id) else { return false }
        return overrides[key] != nil
    }
}
