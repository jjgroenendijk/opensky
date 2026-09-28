// The QUST tail of a VMAD field: the quest-stage fragment table and the
// per-alias script sections.
//
// A quest's stage scripts are not stored as ordinary attached scripts. The
// Creation Kit compiles every stage fragment into one generated script file
// named "QF_<editorID>_<formID>" and gives each fragment a function named
// "Fragment_<n>", numbered in authoring order rather than by stage. The only
// record of which stage and which log entry a numbered fragment belongs to is
// this table, which is why the quest runtime cannot run stage scripts without
// decoding it.
//
// Layout of the section, read straight after the primary script list:
//   int8    extra bind data version — always 2 in shipped data
//   uint16  fragment count
//   wstring file name (no extension), the generated QF_ script
//   fragment[fragment count]:
//     uint16  quest stage index, the same number the QUST INDX field carries
//     int16   unused — always 0
//     int32   log-entry index within that stage
//     int8    unused — always 1
//     wstring script name, normally the same as the file name
//     wstring fragment function name, e.g. "Fragment_5"
//   uint16  alias count
//   alias[alias count]:
//     8 bytes script object reference, read with the *primary* object format
//     int16   version, int16 object format — both restated for this alias
//     uint16  script count, then that many ordinary script entries
//
// xEdit reads the stage index and log-entry index as two uint32 words where
// UESP splits each into a value plus an always-constant half. The two agree
// byte for byte on little-endian; the split spelling is used here because it
// names the halves the constants sit in.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/VMAD Field", section "QUST Records"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/VMAD_Field
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, `wbVMADFragmentedQUST`
//     (line 2929) — 'Script Fragments' struct and the 'Aliases' array.
// Layout documented in docs/formats/vmad.md.

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
