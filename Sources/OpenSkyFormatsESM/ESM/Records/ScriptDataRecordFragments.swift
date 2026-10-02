// The SCEN, PACK, and PERK tails of a VMAD field. SCEN and PACK store a flag
// byte whose set bits count the fragments; PERK stores a uint16 count.
// Layout, sources, and vanilla sweep: docs/formats/vmad.md.

import Foundation
import OpenSkyFormatsCore

/// One fragment: the script that holds it and the generated function name.
nonisolated public struct ScriptFragment: Equatable, Sendable {
    /// SCEN and PACK: the flag bit it answers. PERK: the fragment index.
    public let slot: UInt32
    public let scriptName: String
    public let functionName: String
}

/// One SCEN phase fragment.
nonisolated public struct ScenePhaseFragment: Equatable, Sendable {
    /// Bit 0x01 on start, 0x02 on completion.
    public let phaseFlag: UInt8
    public let phaseIndex: UInt32
    public let scriptName: String
    public let functionName: String
}

/// A decoded SCEN, PACK, or PERK tail.
nonisolated public struct RecordFragmentSection: Equatable, Sendable {
    public let extraBindDataVersion: Int8
    /// SCEN: 0x01 begin, 0x02 end. PACK: 0x01 begin, 0x02 end, 0x04 change. PERK: nil.
    public let flags: UInt8?
    public let fileName: String
    public let fragments: [ScriptFragment]
    /// SCEN only.
    public let phaseFragments: [ScenePhaseFragment]
}

nonisolated extension ScriptDataDecoder {
    /// Decodes the SCEN, PACK, or PERK tail. False leaves the reader where it was.
    public mutating func decodeRecordFragmentTail(ownerType: FourCC) -> RecordFragmentSection? {
        guard ["PACK", "PERK", "SCEN"].contains(ownerType) else { return nil }
        let start = reader.offset
        do {
            let section = try decodeRecordFragments(ownerType: ownerType)
            guard reader.bytesRemaining == 0 else {
                reader.seek(to: start)
                return nil
            }
            return section
        } catch {
            reader.seek(to: start)
            return nil
        }
    }

    private mutating func decodeRecordFragments(ownerType: FourCC) throws -> RecordFragmentSection {
        let bindVersion = try Int8(bitPattern: reader.readUInt8())
        if ownerType == "PERK" {
            let fileName = try readString()
            let count = try checkedCount(
                UInt32(reader.readUInt16()),
                minimumSize: 9,
                context: "fragments"
            )
            let fragments = try (0 ..< count).map { _ in
                let index = try reader.readUInt32()
                reader.skip(1)
                return try ScriptFragment(
                    slot: index,
                    scriptName: readString(),
                    functionName: readString()
                )
            }
            return RecordFragmentSection(
                extraBindDataVersion: bindVersion, flags: nil, fileName: fileName,
                fragments: fragments, phaseFragments: []
            )
        }
        let flags = try reader.readUInt8()
        let fileName = try readString()
        let bits: [UInt32] = ownerType == "PACK" ? [0x01, 0x02, 0x04] : [0x01, 0x02]
        guard UInt32(flags) & ~bits.reduce(0, |) == 0 else {
            throw ScriptDataError.unknownFragmentFlags(recordType: ownerType, flags: flags)
        }
        var fragments: [ScriptFragment] = []
        for bit in bits where UInt32(flags) & bit != 0 {
            reader.skip(1)
            try fragments.append(ScriptFragment(
                slot: bit,
                scriptName: readString(),
                functionName: readString()
            ))
        }
        let phases = ownerType == "SCEN" ? try decodePhaseFragments() : []
        return RecordFragmentSection(
            extraBindDataVersion: bindVersion, flags: flags, fileName: fileName,
            fragments: fragments, phaseFragments: phases
        )
    }

    private mutating func decodePhaseFragments() throws -> [ScenePhaseFragment] {
        let count = try checkedCount(
            UInt32(reader.readUInt16()),
            minimumSize: 10,
            context: "phase fragments"
        )
        return try (0 ..< count).map { _ in
            let flag = try reader.readUInt8()
            let index = try reader.readUInt32()
            reader.skip(1)
            return try ScenePhaseFragment(
                phaseFlag: flag, phaseIndex: index,
                scriptName: readString(), functionName: readString()
            )
        }
    }
}
