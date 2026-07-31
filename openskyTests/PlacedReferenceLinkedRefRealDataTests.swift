// Env-gated XLKR sweep over the user's own Skyrim SE install (read-only
// external input, never committed — AGENTS.md Legal & IP): walks every REFR in
// Skyrim.esm, tallies the on-disk shape of every linked-reference subrecord,
// and pins the numbers `PlacedReference.linkedReference(keyword:)` relies on.
// Skips automatically when OPENSKY_DATA_ROOT is unset (CI has no game data).
//
// The counts are asserted rather than only written to logs/, because print()
// never reaches the .xcresult and a number nobody checks is not evidence.
//
// Layout under test: UESP "Skyrim Mod:Mod File Format/REFR" XLKR row ("8-byte
// struct: formid 0 or KYWD, formid REFR ... 10 instances of 4 byte struct with
// just a formid in Skyrim.esm") and xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas
// line 9910 `wbRArray('Linked References', wbStruct(XLKR, 'Linked Reference',
// [wbFormIDCk('Keyword/Ref', ...), wbFormIDCk('Ref', ...)], cpNormal, False,
// nil, 1))`, whose trailing `1` is `aOptionalFromElement` (wbInterface.pas
// line 4345) and is what makes the second FormID droppable.

import Foundation
@testable import opensky
import Testing

struct PlacedReferenceLinkedRefRealDataTests {
    /// Real data only when explicitly pointed at via the env var; the
    /// locator's Steam-default fallback is deliberately not consulted so
    /// machines without the override skip deterministically.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func sweepsEveryLinkedReferenceInSkyrimESM() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let tally = Self.sweep(file: file)

        try? FileManager.default.createDirectory(
            at: logsDirectory, withIntermediateDirectories: true
        )
        try? tally.summary.write(to: logURL, atomically: true, encoding: .utf8)

        check(tally)
    }

    // MARK: - Assertions

    /// Observed 2026-07-31 over Skyrim.esm (form version 44): 12477 XLKR
    /// subrecords on 11287 of 693333 REFR records; payloads are exactly 8
    /// bytes (12467) or exactly 4 (10). Volume counts are asserted as lower
    /// bounds so a differently patched Skyrim.esm still passes, while the
    /// structural facts the parser depends on are pinned exactly.
    private func check(_ tally: Tally) {
        #expect(tally.references > 690_000, "REFR count far below the observed 693333")
        #expect(tally.referencesWithLinks > 11000, "XLKR carriers far below the observed 11287")
        #expect(tally.fields > 12000, "XLKR subrecords far below the observed 12477")
        #expect(tally.fields == tally.longForm + tally.shortForm + tally.unreadable)
        #expect(tally.unreadable == 0, "XLKR payload too short to hold one FormID")
        #expect(tally.decodedReferencesWithLinks == tally.referencesWithLinks)

        // Only two payload sizes exist, so the 4-byte form is real and nothing
        // in between needs a rule. UESP's REFR page independently states "10
        // instances of 4 byte struct with just a formid in Skyrim.esm".
        #expect(Set(tally.sizeHistogram.keys) == [4, 8], "unexpected XLKR payload size")
        #expect(tally.shortForm == 10, "4-byte XLKR count moved off UESP's stated 10")

        // Field order: every non-null first FormID of the 8-byte form is a KYWD
        // record and no second FormID ever is, which is what makes `keyword`
        // then `ref` the right reading rather than the reverse. The 4-byte
        // form's lone FormID is never a KYWD, so it is the ref, not a tag.
        #expect(tally.keywordSlotNonKeyword.isEmpty, "8-byte XLKR keyword slot held a non-KYWD")
        #expect(tally.refSlotKeyword == 0, "8-byte XLKR ref slot held a KYWD")
        #expect(tally.shortFormKeywords == 0, "4-byte XLKR FormID was a KYWD")

        // A null keyword slot is the common case (10244 of 12477 observed), so
        // decoding it as an untagged link rather than throwing is load-bearing.
        #expect(tally.nullKeywordSlots > 10000, "null keyword slots far below the observed 10244")

        // What `linkedReference(keyword:)` documents: first match and only
        // match agree, because no reference repeats a keyword and none carries
        // more than one untagged link.
        #expect(tally.referencesWithRepeatedKeyword == 0, "a REFR repeats one XLKR keyword")
        #expect(tally.referencesWithMultipleUntagged == 0, "a REFR carries two untagged links")
        #expect(tally.maximumLinksOnOneReference == 19, "deepest link list moved off 19")

        // Every REFR that decodes yields exactly the XLKR fields the raw walk
        // saw, so the parser neither loses nor invents a link.
        #expect(tally.decodeMismatches == 0, "PlacedReference lost or invented a link")
    }

    // MARK: - Sweep

    private struct Tally {
        var references = 0
        var referencesWithLinks = 0
        var decodedReferencesWithLinks = 0
        var decodeMismatches = 0
        var unreadableReferences = 0
        var fields = 0
        var longForm = 0
        var shortForm = 0
        var unreadable = 0
        var nullKeywordSlots = 0
        var sizeHistogram: [Int: Int] = [:]
        var referencesWithRepeatedKeyword = 0
        var referencesWithMultipleUntagged = 0
        var maximumLinksOnOneReference = 0
        var keywordRecords: Set<UInt32> = []
        var keywordSlots: Set<UInt32> = []
        var refSlots: Set<UInt32> = []
        var shortFormIDs: Set<UInt32> = []

        /// 8-byte keyword slots that are not KYWD records, and short-form
        /// FormIDs that are — both empty is what proves the field order.
        var keywordSlotNonKeyword: Set<UInt32> {
            keywordSlots.subtracting(keywordRecords)
        }

        var refSlotKeyword: Int {
            refSlots.intersection(keywordRecords).count
        }

        var shortFormKeywords: Int {
            shortFormIDs.intersection(keywordRecords).count
        }

        var summary: String {
            let sizes = sizeHistogram.sorted { $0.key < $1.key }
                .map { "\($0.key)B:\($0.value)" }.joined(separator: " ")
            return """
            [INFO] Skyrim.esm XLKR sweep: \(fields) subrecords over \
            \(referencesWithLinks)/\(references) REFR records
            [INFO] payload sizes: \(sizes) (8-byte form \(longForm), 4-byte form \(shortForm), \
            unreadable \(unreadable))
            [INFO] null keyword slots in the 8-byte form: \(nullKeywordSlots)
            [INFO] distinct keyword slots \(keywordSlots.count), of which non-KYWD \
            \(keywordSlotNonKeyword.count); ref slots that are KYWD \(refSlotKeyword); \
            short-form FormIDs \(shortFormIDs.count), of which KYWD \(shortFormKeywords)
            [INFO] references repeating one keyword: \(referencesWithRepeatedKeyword); \
            references with more than one untagged link: \(referencesWithMultipleUntagged); \
            most links on one reference: \(maximumLinksOnOneReference)
            [INFO] PlacedReference decode mismatches: \(decodeMismatches); \
            decoded references with links: \(decodedReferencesWithLinks); \
            unreadable REFR records: \(unreadableReferences)
            """
        }
    }

    private static func sweep(file: ESMFile) -> Tally {
        var tally = Tally()
        ESMWalk.forEachRecord(in: file) { record in
            switch record.type {
            case "KYWD":
                tally.keywordRecords.insert(record.formID)
            case "REFR":
                accumulate(record: record, into: &tally)
            default:
                break
            }
            return true
        }
        return tally
    }

    private static func accumulate(record: ESMRecord, into tally: inout Tally) {
        tally.references += 1
        guard let fields = try? record.fields() else {
            tally.unreadableReferences += 1
            return
        }
        let payloads = fields.filter { $0.type == "XLKR" }.map(\.data)
        guard !payloads.isEmpty else { return }
        tally.referencesWithLinks += 1
        tally.fields += payloads.count
        tally.maximumLinksOnOneReference = max(
            tally.maximumLinksOnOneReference, payloads.count
        )
        var keywords: [UInt32] = []
        var untagged = 0
        for payload in payloads {
            classify(payload: payload, keywords: &keywords, untagged: &untagged, into: &tally)
        }
        if keywords.count != Set(keywords).count {
            tally.referencesWithRepeatedKeyword += 1
        }
        if untagged > 1 {
            tally.referencesWithMultipleUntagged += 1
        }
        compare(record: record, payloads: payloads.count, into: &tally)
    }

    private static func classify(
        payload: Data,
        keywords: inout [UInt32],
        untagged: inout Int,
        into tally: inout Tally
    ) {
        tally.sizeHistogram[payload.count, default: 0] += 1
        var reader = BinaryReader(payload)
        guard let first = try? reader.readUInt32() else {
            tally.unreadable += 1
            return
        }
        guard payload.count >= 8, let second = try? reader.readUInt32() else {
            tally.shortForm += 1
            tally.shortFormIDs.insert(first)
            untagged += 1
            return
        }
        tally.longForm += 1
        tally.refSlots.insert(second)
        if first == 0 {
            tally.nullKeywordSlots += 1
            untagged += 1
        } else {
            tally.keywordSlots.insert(first)
            keywords.append(first)
        }
    }

    /// Re-decodes the record through the production parser so the sweep proves
    /// what ships, not a second implementation of the same layout.
    private static func compare(record: ESMRecord, payloads: Int, into tally: inout Tally) {
        guard let reference = try? PlacedReference(record: record) else { return }
        tally.decodedReferencesWithLinks += 1
        if reference.linkedReferences.count != payloads {
            tally.decodeMismatches += 1
        }
    }

    // MARK: - Artifacts

    private var logURL: URL {
        logsDirectory.appending(path: "xlkr-sweep.log")
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // openskyTests/
            .deletingLastPathComponent() // repo root
            .appending(path: "logs")
    }
}
