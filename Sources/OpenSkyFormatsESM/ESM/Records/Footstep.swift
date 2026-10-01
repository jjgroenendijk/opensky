// FSTP footstep and FSTS footstep set. A footstep names the tag the behavior
// graph raises and the impact data set that turns it into a sound. XCNT counts
// run walk-first, but the DATA lists run swim-first.
// Layout and evidence: docs/formats/footstep.md.

import Foundation
import OpenSkyFormatsCore

/// Which of a footstep set's five lists a lookup wants. The raw values are the
/// DATA array order, not the XCNT order, because that is what the decoder
/// walks.
nonisolated public enum FootstepGait: Int, CaseIterable, Sendable {
    case swimming
    case sneaking
    case sprinting
    case running
    case walking
}

/// One FSTP: a tag the behavior graph raises paired with the impact data set
/// that resolves the tag to a sound for the surface under the foot.
nonisolated public struct Footstep: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    /// DATA -> IPDS. Nil when absent or null, which leaves this footstep silent
    /// rather than unresolvable.
    public let impactDataSet: FormID?
    /// ANAM. The behavior-graph event name that fires this footstep, spelled
    /// exactly as `0_master.hkx` declares it (`FootLeft`, `FootScuffRight`,
    /// `JumpDown`, ...). Nil when the record carries no ANAM.
    public let tag: String?

    public init(record: ESMRecord) throws {
        guard record.type == "FSTP" else {
            throw ESMError.malformed("expected FSTP record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var impactDataSet: FormID?
        var tag: String?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "DATA":
                guard field.data.count == 4 else { break }
                let id = try FormID(reader.readUInt32())
                impactDataSet = id.isNull ? nil : id
            case "ANAM":
                tag = try reader.readZString()
            default:
                break
            }
        }
        self.editorID = editorID
        self.impactDataSet = impactDataSet
        self.tag = tag
    }
}

/// One FSTS: five per-gait lists of FSTP FormIDs.
nonisolated public struct FootstepSet: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    /// The five lists, indexed by `FootstepGait.rawValue`. Always five entries,
    /// any of which may be empty.
    private let lists: [[FormID]]

    public init(record: ESMRecord) throws {
        guard record.type == "FSTS" else {
            throw ESMError.malformed("expected FSTS record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var counts: [Int] = []
        var footsteps: [FormID] = []
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "XCNT":
                counts = try Self.readCounts(&reader, size: field.data.count)
            case "DATA":
                while reader.bytesRemaining >= 4 {
                    try footsteps.append(FormID(reader.readUInt32()))
                }
            default:
                break
            }
        }
        self.editorID = editorID
        lists = Self.split(footsteps, counts: counts)
    }

    /// Test seam and the shape the store hands back for a set it synthesized.
    public init(formID: FormID, editorID: String?, lists: [FootstepGait: [FormID]]) {
        self.formID = formID
        self.editorID = editorID
        self.lists = FootstepGait.allCases.map { lists[$0] ?? [] }
    }

    /// The footsteps for one gait, in record order.
    public func footsteps(for gait: FootstepGait) -> [FormID] {
        lists[gait.rawValue]
    }

    /// XCNT is a fixed 20-byte struct of five uint32 counts in the order
    /// walking, running, sprinting, sneaking, swimming. A payload that is not
    /// exactly that shape leaves the counts empty, and the whole DATA array
    /// then lands in no list at all rather than being sliced at guessed
    /// boundaries.
    private static func readCounts(
        _ reader: inout BinaryReader,
        size: Int
    ) throws -> [Int] {
        guard size == 20 else { return [] }
        var counts: [Int] = []
        for _ in 0 ..< 5 {
            try counts.append(Int(reader.readUInt32()))
        }
        return counts
    }

    /// Slices the flat DATA array into the five per-gait lists. `counts` is in
    /// XCNT order, the array in DATA order, so counts are used back to front.
    /// If the counts do not match, lists take what is left; extra IDs drop.
    private static func split(_ footsteps: [FormID], counts: [Int]) -> [[FormID]] {
        guard counts.count == 5 else {
            return Array(repeating: [], count: 5)
        }
        var lists: [[FormID]] = []
        var start = 0
        for gait in FootstepGait.allCases {
            let wanted = max(0, counts[4 - gait.rawValue])
            let end = min(footsteps.count, start + wanted)
            lists.append(start < end ? Array(footsteps[start ..< end]) : [])
            start = end
        }
        return lists
    }
}
