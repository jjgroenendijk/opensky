// The QUST tail of a VMAD field: the stage fragment table and the per-alias
// script sections. Stage fragments compile into one "QF_<editorID>_<formID>"
// script, and only this table says which stage and log entry each
// "Fragment_<n>" belongs to. Layout and sources: docs/formats/vmad.md.

import Foundation

/// One entry of the quest-stage fragment table.
nonisolated public struct QuestFragment: Equatable, Sendable {
    /// Quest stage this fragment runs for, matching a QUST INDX stage index.
    public let stageIndex: UInt16
    /// Log entry within that stage. Signed on disk; vanilla writes 0 or a
    /// small positive index.
    public let logEntryIndex: Int32
    /// Script the function lives on — normally the section's file name.
    public let scriptName: String
    /// Generated function name, e.g. "Fragment_5".
    public let functionName: String
}

/// The scripts one quest alias carries, which live in the VMAD tail rather
/// than in the ALST/ALLS block that defines the alias.
nonisolated public struct QuestAliasScripts: Equatable, Sendable {
    /// Quest and alias the scripts attach to. The FormID is the owning quest
    /// in every file the official tools produce, but the engine permits a
    /// cross-quest reference, so it is carried rather than assumed.
    public let object: ScriptObjectReference
    /// Restated per alias. UESP notes it always equals the primary version.
    public let version: Int16
    /// Restated per alias, likewise always the primary object format.
    public let objectFormat: ScriptObjectFormat
    public let scripts: [AttachedScript]

    /// Alias slot on `object`, or nil when the section names a direct FormID
    /// instead of an alias, which no shipped file does.
    public var aliasID: Int16? {
        object.isAlias ? object.alias : nil
    }
}

/// The whole decoded QUST fragment tail.
nonisolated public struct QuestFragmentSection: Equatable, Sendable {
    /// The leading int8. Always 2; anything else means the Creation Kit would
    /// have failed to load alias script data, so it is recorded, not enforced.
    public let extraBindDataVersion: Int8
    /// Generated fragment script, "QF_<editorID>_<formID>" by convention.
    public let fileName: String
    /// The authored count, kept for diagnostics the way COCT and KSIZ are.
    public let declaredFragmentCount: Int
    public let fragments: [QuestFragment]
    public let aliasScripts: [QuestAliasScripts]

    public var isEmpty: Bool {
        fragments.isEmpty && aliasScripts.isEmpty
    }

    /// True when the authored count disagrees with the fragments decoded.
    public var fragmentCountMismatch: Bool {
        declaredFragmentCount != fragments.count
    }

    /// Fragments attached to `stage`, in file order.
    public func fragments(forStage stage: UInt16) -> [QuestFragment] {
        fragments.filter { $0.stageIndex == stage }
    }
}
