// Flags, numbers, and form links a script set on one form that no record field or
// other runtime holds, such as `SetGhost` or `SetCrimeFaction`. The natives that set
// them read them back. Saved in the `SCRS` chunk. See docs/engine/papyrus-script-state.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

nonisolated public struct ScriptedReferenceState: WorldStateComponent, Sendable {
    /// Keyed by a lowercased name, such as `ghost`.
    public private(set) var flags: [String: Bool]
    public private(set) var values: [String: Float]
    public private(set) var forms: [String: ReferenceKey]
    /// Forms a script added to a list, in the order added.
    public private(set) var addedForms: [ReferenceKey]

    public static var componentKind: WorldStateComponentKind {
        .scriptedState
    }

    public init(
        flags: [String: Bool] = [:],
        values: [String: Float] = [:],
        forms: [String: ReferenceKey] = [:],
        addedForms: [ReferenceKey] = []
    ) {
        self.flags = Dictionary(flags.map { ($0.key.lowercased(), $0.value) }) { _, last in last }
        self.values = Dictionary(values.map { ($0.key.lowercased(), $0.value) }) { _, last in last }
        self.forms = Dictionary(forms.map { ($0.key.lowercased(), $0.value) }) { _, last in last }
        self.addedForms = addedForms
    }

    public var isEmpty: Bool {
        flags.isEmpty && values.isEmpty && forms.isEmpty && addedForms.isEmpty
    }

    public func flag(_ name: String) -> Bool? {
        flags[name.lowercased()]
    }

    public func value(_ name: String) -> Float? {
        values[name.lowercased()]
    }

    public func form(_ name: String) -> ReferenceKey? {
        forms[name.lowercased()]
    }

    public mutating func setFlag(_ name: String, _ flag: Bool?) {
        flags[name.lowercased()] = flag
    }

    public mutating func setValue(_ name: String, _ value: Float?) {
        values[name.lowercased()] = value
    }

    public mutating func setForm(_ name: String, _ form: ReferenceKey?) {
        forms[name.lowercased()] = form
    }

    public mutating func setAddedForms(_ forms: [ReferenceKey]) {
        addedForms = forms
    }
}

nonisolated extension WorldStateComponentKind {
    /// Script-set flags and links. Keyed by the form the script changed.
    public static let scriptedState = Self(
        rawValue: "scriptedState", order: 35, affectsCellBuild: false
    )
}
