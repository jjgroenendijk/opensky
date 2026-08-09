// The INFO tail of a VMAD field: the begin/end result-script fragments a
// dialogue response runs when it is chosen (issue #426, roadmap item 17.2).
//
// A dialogue result script is not an ordinary attached script. The Creation Kit
// compiles the two result boxes of one response into a single generated script
// file named "TIF_<editorID>_<formID>" — and since most INFO records carry no
// editor ID, in shipped data that is "TIF__<formID>" with two underscores — and
// gives each box a function named "Fragment_<n>". Which box a numbered fragment
// belongs to is not in its name: it is the position of the entry in this table,
// read against the flag bits. That is why the dialogue runtime cannot run a
// result script without decoding the tail.
//
// Layout of the section, read straight after the primary script list:
//   int8    extra bind data version — always 2 in shipped data
//   uint8   flags: 0x1 has a begin fragment, 0x2 has an end fragment
//   wstring file name (no extension), the generated TIF_ script
//   fragment[number of set flag bits], in bit order (begin, then end):
//     int8    unused — always 1 in shipped data
//     wstring script name, normally the same as the file name
//     wstring fragment function name, e.g. "Fragment_0"
//
// Unlike QUST's table, the fragment count is not stored: it is the population
// count of the flag byte. UESP states this directly ("Variable flagsCount is
// the number of bit flags activated in flags") and xEdit spells the same rule
// as `wbScriptFragmentsInfoCounter` over an array with no count path.
//
// The vanilla sweep behind these statements: all 7,661 INFO VMAD tails across
// the five shipped masters decode with zero bytes left over, every one declares
// version 2, every unused fragment byte is 1, every script name equals the file
// name, and the flag byte is only ever 1, 2 or 3. Recorded in
// docs/formats/vmad.md.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/VMAD Field", section "INFO Records"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/VMAD_Field
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, `wbVMADFragmentedINFO`
//     (line 2752) — the 'Script Fragments' struct and its flag-counted array.

import Foundation

/// Which result box of a dialogue response a fragment came from.
///
/// The Creation Kit's Topic Info window offers two script boxes, "Begin" and
/// "End", and the flag bits name them in that order. OpenSky keeps them apart
/// rather than flattening the pair, because the two run at opposite ends of a
/// response and a caller that runs both at once would set a quest stage before
/// the line it belongs to was ever delivered.
nonisolated enum TopicInfoFragmentPhase: Equatable, Sendable, CaseIterable {
    /// Runs as the response starts.
    case begin
    /// Runs once the response has finished.
    case end

    /// Bit in the tail's flag byte that declares this phase present.
    var flagBit: UInt8 {
        switch self {
        case .begin: 1 << 0
        case .end: 1 << 1
        }
    }
}

/// One entry of the INFO fragment table.
nonisolated struct TopicInfoFragment: Equatable {
    /// Result box this fragment came from, derived from its position against
    /// the flag bits rather than from anything stored in the entry.
    let phase: TopicInfoFragmentPhase
    /// Script the function lives on — normally the section's file name.
    let scriptName: String
    /// Generated function name, e.g. "Fragment_0".
    let functionName: String
}

/// The whole decoded INFO fragment tail.
nonisolated struct TopicInfoFragmentSection: Equatable {
    /// The leading int8. Always 2 in shipped data; anything else means the
    /// Creation Kit would have failed to load the section, so it is recorded,
    /// not enforced.
    let extraBindDataVersion: Int8
    /// The raw flag byte, kept because a bit outside 0x1 and 0x2 is a fact
    /// about the file that the decoded fragment list cannot express.
    let flags: UInt8
    /// Generated fragment script, "TIF_<editorID>_<formID>" by convention.
    let fileName: String
    let fragments: [TopicInfoFragment]

    var isEmpty: Bool {
        fragments.isEmpty
    }

    /// The fragment for one result box, or nil when the response has no script
    /// in it.
    func fragment(_ phase: TopicInfoFragmentPhase) -> TopicInfoFragment? {
        fragments.first { $0.phase == phase }
    }
}
