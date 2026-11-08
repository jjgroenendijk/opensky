// The INFO tail of a VMAD field: the begin and end result-script fragments of a
// dialogue response, compiled into one "TIF__<formID>" script. The fragment
// count is not stored; it is the number of set flag bits.
// Layout, sources, and vanilla sweep: docs/formats/vmad.md.

import Foundation

/// Which result box of a dialogue response a fragment came from. The two run at
/// opposite ends of a response, so they stay apart: running both at once would
/// set a quest stage before its line is spoken.
nonisolated public enum TopicInfoFragmentPhase: Equatable, Sendable, CaseIterable {
    /// Runs as the response starts.
    case begin
    /// Runs once the response has finished.
    case end

    /// Bit in the tail's flag byte that declares this phase present.
    public var flagBit: UInt8 {
        switch self {
        case .begin: 1 << 0
        case .end: 1 << 1
        }
    }
}

/// One entry of the INFO fragment table.
nonisolated public struct TopicInfoFragment: Equatable, Sendable {
    /// Result box this fragment came from, derived from its position against
    /// the flag bits rather than from anything stored in the entry.
    public let phase: TopicInfoFragmentPhase
    /// Script the function lives on — normally the section's file name.
    public let scriptName: String
    /// Generated function name, e.g. "Fragment_0".
    public let functionName: String
}

/// The whole decoded INFO fragment tail.
nonisolated public struct TopicInfoFragmentSection: Equatable, Sendable {
    /// The leading int8. Always 2 in shipped data; anything else means the
    /// Creation Kit would have failed to load the section, so it is recorded,
    /// not enforced.
    public let extraBindDataVersion: Int8
    /// The raw flag byte, kept because a bit outside 0x1 and 0x2 is a fact
    /// about the file that the decoded fragment list cannot express.
    public let flags: UInt8
    /// Generated fragment script, "TIF_<editorID>_<formID>" by convention.
    public let fileName: String
    public let fragments: [TopicInfoFragment]

    public var isEmpty: Bool {
        fragments.isEmpty
    }

    /// The fragment for one result box, or nil when the response has no script
    /// in it.
    public func fragment(_ phase: TopicInfoFragmentPhase) -> TopicInfoFragment? {
        fragments.first { $0.phase == phase }
    }
}
