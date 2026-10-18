// Pure rules behind the World > Runtime State panel: FormID parsing, journal
// lines, and the lookup tables the coordinator caches.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsESM
import OpenSkyWorldState

nonisolated public enum RuntimeStateCore {
    /// Hexadecimal with an optional `0x` prefix. Anything else is nil, so a typo
    /// reports "no change" instead of mutating an unrelated object.
    public static func parseFormID(_ text: String) -> FormID? {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if digits.hasPrefix("0x") {
            digits.removeFirst(2)
        }
        guard !digits.isEmpty, digits.count <= 8, let raw = UInt32(digits, radix: 16) else {
            return nil
        }
        return FormID(raw)
    }

    public static func journalLine(_ entry: WorldStateJournalEntry) -> String {
        let verb = entry.isReset ? "reset" : "set"
        return "\(entry.sequence) \(verb) \(entry.kind.rawValue) \(entry.key.description)"
    }

    /// Same shape as `journalLine(_:)`, so the merged tail reads as one log.
    public static func globalJournalLine(
        _ entry: WorldStateGlobalJournalEntry, name: String
    ) -> String {
        guard let newValue = entry.newValue else {
            return "\(entry.sequence) reset global \(name)"
        }
        return "\(entry.sequence) set global \(name) = \(globalValueText(newValue))"
    }

    /// A short or long global reads as an integer; a float keeps its fraction.
    public static func globalValueText(_ value: GlobalValue) -> String {
        if let integer = value.integerValue {
            return String(integer)
        }
        return String(format: "%g", value.value)
    }

    /// Both rings share one sequence counter, so sorting by it restores the
    /// order the session wrote them in. Each ring is oldest-first.
    public static func journalTail(
        entries: [WorldStateJournalEntry],
        globalEntries: [WorldStateGlobalJournalEntry],
        names: [ReferenceKey: String],
        limit: Int = RuntimeStateSnapshot.journalTailLimit
    ) -> [String] {
        var merged: [(sequence: UInt64, line: String)] = entries.suffix(limit)
            .map { ($0.sequence, journalLine($0)) }
        merged.append(contentsOf: globalEntries.suffix(limit).map {
            ($0.sequence, globalJournalLine($0, name: names[$0.key] ?? $0.key.description))
        })
        return merged.sorted { $0.sequence < $1.sequence }.suffix(limit).map(\.line)
    }

    public static func globalTypeName(_ type: Global.ValueType) -> String {
        switch type {
        case .short: "short"
        case .long: "long"
        case .float: "float"
        }
    }

    public static func clampTimescale(_ timescale: Float) -> Float {
        min(
            max(GameClock.timescaleRange.lowerBound, timescale),
            GameClock.timescaleRange.upperBound
        )
    }

    public static func globalNamesByKey(_ store: GlobalStore?) -> [ReferenceKey: String] {
        var names: [ReferenceKey: String] = [:]
        for global in store?.sortedGlobals() ?? [] {
            guard let editorID = global.editorID, let key = store?.key(for: global.formID)
            else { continue }
            names[key] = editorID
        }
        return names
    }

    /// Music tracks with at least one condition, by editor ID or FormID. A
    /// duplicate name keeps the lowest FormID, so a name never retargets.
    public static func conditionSources(_ store: MusicRecordStore?) -> [String: FormID] {
        let tracks = (store?.musicTracks.values).map {
            $0.sorted { $0.formID.rawValue < $1.formID.rawValue }
        } ?? []
        var sources: [String: FormID] = [:]
        for track in tracks where !track.conditions.isEmpty {
            let name = track.editorID ?? track.formID.description
            if sources[name] == nil {
                sources[name] = track.formID
            }
        }
        return sources
    }
}
