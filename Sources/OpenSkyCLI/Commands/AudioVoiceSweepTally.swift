// Accumulators for `audio voice-sweep`. Counts and histograms only — no file
// bytes are retained, which is what keeps the sweep's footprint flat over the
// whole voice corpus. Satellite of AudioVoiceSweep.swift.

import Foundation

/// Name-derivation result, per plugin and in total.
struct VoiceNameReport {
    struct Row {
        let plugin: String
        let derived: Int
        let actual: Int
        /// Archive names the derivation reproduced.
        let matched: Int
        /// Archive names whose response the records do carry, spelled some
        /// other way — the ones that would mean the naming rule is wrong.
        let unmatchedRule: [String]
        /// Archive names naming a FormID and response no INFO in the plugin
        /// carries at all. These are recordings whose INFO was cut or
        /// renumbered after the audio was exported; no naming rule reaches
        /// them.
        let unknownResponse: [String]
    }

    /// Unexplained names printed per plugin. Vanilla leaves a handful of
    /// developer leftovers ("duplicate_filename", "_newline") behind, and a
    /// silent cap would read as a clean sweep.
    static let printLimit = 12

    private(set) var rows: [Row] = []

    mutating func record(
        plugin: String, derived: [VoiceFileNameDerivation], actual: Set<String>
    ) {
        let names = Set(derived.map(\.name))
        let missing = actual.subtracting(names)
        // Index the derivations by their `<formid>_<n>` tail so an unexplained
        // archive name can be printed beside the name the rule produced for the
        // same response, and beside the editor IDs that produced it. Without
        // the pairing a mismatch says nothing about which half of the rule is
        // wrong.
        var derivedByTail: [String: VoiceFileNameDerivation] = [:]
        for derivation in derived {
            derivedByTail[Self.tail(of: derivation.name)] = derivation
        }
        var unmatchedRule: [String] = []
        var unknownResponse: [String] = []
        for name in missing.sorted() {
            guard let derivation = derivedByTail[Self.tail(of: name)] else {
                unknownResponse.append(name)
                continue
            }
            let quest = derivation.questEditorID ?? "<none>"
            let topic = derivation.topicEditorID ?? "<none>"
            unmatchedRule.append(
                "\(name) (rule derives \(derivation.name) from quest \(quest), topic \(topic))"
            )
        }
        rows.append(
            Row(
                plugin: plugin,
                derived: names.count,
                actual: actual.count,
                matched: actual.count - missing.count,
                unmatchedRule: unmatchedRule,
                unknownResponse: unknownResponse
            )
        )
    }

    /// The `<8 hex formid>_<response>.fuz` tail, which identifies the response
    /// independently of the quest and topic halves of the name.
    private static func tail(of name: String) -> String {
        let parts = name.split(separator: "_")
        guard parts.count >= 2 else { return name }
        return parts.suffix(2).joined(separator: "_")
    }

    func print() {
        var totalActual = 0
        var totalMatched = 0
        var totalUnmatchedRule = 0
        for row in rows {
            totalActual += row.actual
            totalMatched += row.matched
            totalUnmatchedRule += row.unmatchedRule.count
            Swift.print(
                "[INFO] voice names \(row.plugin): \(row.actual) archive names, "
                    + "\(row.derived) derived from records, \(row.matched) explained, "
                    + "\(row.unmatchedRule.count) spelled differently, "
                    + "\(row.unknownResponse.count) naming no INFO response"
            )
            print(row.unmatchedRule, label: "spelled differently")
            print(row.unknownResponse, label: "names no INFO response")
        }
        let percentage = totalActual == 0 ? 0 : Double(totalMatched) / Double(totalActual) * 100
        Swift.print(
            "[INFO] voice names total: \(totalMatched) of \(totalActual) explained "
                + String(format: "(%.3f%%)", percentage)
                + ", \(totalUnmatchedRule) spelled differently"
        )
    }

    private func print(_ names: [String], label: String) {
        for name in names.prefix(Self.printLimit) {
            Swift.print("[INFO]   \(label): \(name)")
        }
        if names.count > Self.printLimit {
            Swift.print(
                "[INFO]   ... \(names.count - Self.printLimit) more \(label) not printed"
            )
        }
    }
}

/// Framing result over the `.fuz` corpus.
struct VoiceFramingTally {
    var framed = 0
    var withLip = 0
    var totalLipBytes = 0
    var totalAudioBytes = 0
    var totalDuration = 0.0
    var versions: [UInt32: Int] = [:]
    var channelCounts: [Int: Int] = [:]
    var sampleRates: [Int: Int] = [:]
    var formatTags: [UInt16: Int] = [:]
    var unsupported = 0
    var skipped = 0
    var failures: [(String, String)] = []

    mutating func record(_ file: FUZFile) {
        framed += 1
        versions[file.version, default: 0] += 1
        if file.lipByteCount > 0 {
            withLip += 1
            totalLipBytes += file.lipByteCount
        }
        totalAudioBytes += file.audioByteCount
    }

    mutating func record(_ audio: XWMFile) {
        formatTags[audio.codec.formatTag, default: 0] += 1
        channelCounts[audio.codec.channelCount, default: 0] += 1
        sampleRates[audio.codec.sampleRate, default: 0] += 1
        totalDuration += audio.declaredDuration ?? 0
    }

    mutating func note(path: String, error: FUZError) {
        switch error {
        case let .unsupported(reason):
            unsupported += 1
            Swift.print("[INFO] \(path): unsupported (\(reason)), accounted")
        case let .malformed(reason):
            failures.append((path, "malformed: \(reason)"))
        }
    }

    mutating func note(path: String, error: XWMError) {
        switch error {
        case let .unsupported(reason):
            unsupported += 1
            Swift.print("[INFO] \(path): audio unsupported (\(reason)), accounted")
        case let .malformed(reason):
            failures.append((path, "audio malformed: \(reason)"))
        }
    }

    func print(total: Int) {
        for failure in failures.prefix(20) {
            printError("[ERROR] \(failure.0): \(failure.1)")
        }
        Swift.print(
            "[INFO] voice framing: \(total) entries, \(total - skipped) walked, "
                + "\(skipped) skipped by --limit, \(framed) framed, "
                + "\(unsupported) unsupported, \(failures.count) failed"
        )
        Swift.print(
            "[INFO] voice lip: \(withLip) with a lip blob, \(framed - withLip) without, "
                + "\(totalLipBytes) lip bytes"
        )
        let minutes = String(format: "%.1f", totalDuration / 60)
        Swift.print(
            "[INFO] voice audio: \(totalAudioBytes) payload bytes, \(minutes) minutes declared"
        )
        let tags = formatTags.mapKeys { "0x" + String(format: "%04X", $0) }
        Swift.print(
            "[INFO] voice audio format: versions "
                + histogram(versions.mapKeys(String.init))
                + "; format " + histogram(tags)
                + "; channels " + histogram(channelCounts.mapKeys(String.init))
                + "; rates " + histogram(sampleRates.mapKeys(String.init))
        )
    }

    private func histogram(_ counts: [String: Int]) -> String {
        counts.sorted { $0.key < $1.key }
            .map { "\($0.key) x\($0.value)" }
            .joined(separator: ", ")
    }
}
