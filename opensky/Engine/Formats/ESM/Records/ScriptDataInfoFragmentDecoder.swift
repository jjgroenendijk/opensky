// The INFO tail of a VMAD field, decoded on top of the primary-script decoder
// in ScriptDataDecoder.swift, exactly as the QUST tail is. It lives in its own
// file so that decoder's type body stays inside the strict-lint cap.
//
// Layout and references: ScriptDataInfoFragments.swift.

import Foundation

nonisolated extension ScriptDataDecoder {
    /// Decodes the INFO tail, reporting whether the whole remainder was
    /// consumed. A malformed tail is not fatal: the caller falls back to the
    /// recorded skip, so the primary scripts of a response with a broken
    /// fragment table still reach the runtime (AGENTS.md mod-quirk rule).
    mutating func decodeInfoFragmentTail() -> Bool {
        let start = reader.offset
        do {
            let section = try decodeInfoFragments()
            guard reader.bytesRemaining == 0 else {
                reader.seek(to: start)
                return false
            }
            infoFragments = section
            return true
        } catch {
            reader.seek(to: start)
            return false
        }
    }

    mutating func decodeInfoFragments() throws -> TopicInfoFragmentSection {
        let bindVersion = try Int8(bitPattern: reader.readUInt8())
        let flags = try reader.readUInt8()
        let fileName = try readString()
        // The count is the population of the flag byte rather than a stored
        // number, and the entries arrive in bit order. A bit outside the two
        // documented ones therefore cannot be paired with a phase, so the
        // section is refused rather than silently mis-attributed — the caller
        // keeps the primary scripts and tallies the tail.
        guard
            flags & ~(TopicInfoFragmentPhase.begin.flagBit
                | TopicInfoFragmentPhase.end.flagBit) == 0
        else {
            throw ScriptDataError.unknownFragmentFlags(recordType: "INFO", flags: flags)
        }
        var fragments: [TopicInfoFragment] = []
        for phase in TopicInfoFragmentPhase.allCases where flags & phase.flagBit != 0 {
            reader.skip(1) // always 1
            try fragments.append(TopicInfoFragment(
                phase: phase,
                scriptName: readString(),
                functionName: readString()
            ))
        }
        return TopicInfoFragmentSection(
            extraBindDataVersion: bindVersion,
            flags: flags,
            fileName: fileName,
            fragments: fragments
        )
    }
}
