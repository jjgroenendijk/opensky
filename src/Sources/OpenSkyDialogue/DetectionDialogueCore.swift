// Which detection line a combat group says when its record of a target changes, and
// the waits between lines, kept per group and per subtype. Values in, values out.
// See docs/engine/combat-detection-dialogue.md.

import Foundation
import OpenSkyConditions
public import OpenSkyDialogueInterface
public import OpenSkyFormatsESM
import simd

/// What the detection dialogue keeps between passes.
nonisolated public struct DetectionDialogueState: Equatable, Sendable {
    /// One group: the actors that fight one target.
    struct Group: Equatable, Sendable {
        var record = DetectionRecord.normal
        /// The members at the last pass, with where they stood.
        var members: [ReferenceKey: SIMD3<Float>] = [:]
        /// When each subtype may next be said.
        var readyAt: [DetectionSubtype: Double] = [:]
        var nextSearchUpdate: Double = 0
    }

    var groups: [ReferenceKey: Group] = [:]
    var random = ConditionRandom(seed: 0x4445_5444)

    public init() {}

    /// Each target a group has a record of, for a state read.
    public var records: [ReferenceKey: DetectionRecord] {
        groups.mapValues(\.record)
    }

    /// Seconds until `subtype` may be said about `target`; 0 when it may be said now.
    public func wait(for subtype: DetectionSubtype, about target: ReferenceKey, now: Double)
        -> Double
    {
        max(0, (groups[target]?.readyAt[subtype] ?? 0) - now)
    }
}

nonisolated public enum DetectionDialogueCore {
    /// Seconds between two search updates of one group.
    static let searchUpdateSeconds: Double = 1
    /// The wait after a line of a change. The program's own values; no setting.
    static let changeWait: ClosedRange<Double> = 1 ... 3

    /// One pass: moves each group's record on, and asks `say` for each line. A wait
    /// starts only when `say` answers true, so a group with no line may try again.
    public static func pass(
        _ frame: DetectionDialogueFrame,
        idleWait: ClosedRange<Double>,
        state: inout DetectionDialogueState,
        say: (DetectionLineRequest) -> Bool
    ) {
        let npcs = frame.members.filter { $0.key != .player }
        let byTarget = Dictionary(grouping: npcs, by: \.target)
        let targets = Set(byTarget.keys).union(state.groups.keys).sorted()
        for target in targets {
            var group = state.groups[target] ?? DetectionDialogueState.Group()
            let members = (byTarget[target] ?? []).sorted { $0.key < $1.key }
            let pass = GroupPass(
                frame: frame, target: target, members: members, idleWait: idleWait
            )
            pass.advance(&group, random: &state.random, say: say)
            state.groups[target] = group.record == .normal ? nil : group
        }
    }

    /// The record a group has of its target now. A group that only searches has lost a
    /// target it saw, and is alert about one it never saw.
    static func record(of members: [DetectionMember], previous: DetectionRecord)
        -> DetectionRecord
    {
        guard !members.isEmpty else { return .normal }
        if members.contains(where: { !$0.isSearching }) {
            return .combat
        }
        return previous == .combat || previous == .lost ? .lost : .alert
    }

    static func roll(_ range: ClosedRange<Double>, _ random: inout ConditionRandom) -> Double {
        let unit = Double(random.next() % 1_000_000) / 1_000_000
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}

nonisolated extension DetectionDialogueCore {
    /// One group's facts for one pass.
    struct GroupPass {
        let frame: DetectionDialogueFrame
        let target: ReferenceKey
        let members: [DetectionMember]
        let idleWait: ClosedRange<Double>

        func advance(
            _ group: inout DetectionDialogueState.Group,
            random: inout ConditionRandom,
            say: (DetectionLineRequest) -> Bool
        ) {
            let before = group.record
            let after = DetectionDialogueCore.record(of: members, previous: before)
            group.record = after
            if before != after {
                change((before, after), group: &group, random: &random, say: say)
            } else if after == .alert || after == .lost, frame.now >= group.nextSearchUpdate {
                group.nextSearchUpdate = frame.now + DetectionDialogueCore.searchUpdateSeconds
                let speakers = members.filter(\.canSpeak)
                if !speakers.isEmpty {
                    let speaker = speakers[Int(random.next() % UInt64(speakers.count))].key
                    let subtype: DetectionSubtype = after == .lost ? .lostIdle : .alertIdle
                    speak((subtype, speaker), group: &group, random: &random, say: say)
                }
            }
            if !members.isEmpty {
                group.members = Dictionary(members.map { ($0.key, $0.feet) }) { first, _ in first }
            }
        }

        private func change(
            _ records: (before: DetectionRecord, after: DetectionRecord),
            group: inout DetectionDialogueState.Group,
            random: inout ConditionRandom,
            say: (DetectionLineRequest) -> Bool
        ) {
            let line: (subtype: DetectionSubtype, speaker: ReferenceKey?)?
            switch records {
            case (.normal, .combat):
                line = (.normalToCombat, members.first(where: \.canSpeak)?.key)
            case (.normal, .alert):
                line = (.normalToAlert, members.first(where: \.canSpeak)?.key)
            case (.combat, .lost):
                // The idle waits are rolled when the search starts.
                let wait = DetectionDialogueCore.roll(idleWait, &random)
                group.readyAt[.alertIdle] = frame.now + wait
                group.readyAt[.lostIdle] = frame.now + wait
                group.nextSearchUpdate = frame.now + DetectionDialogueCore.searchUpdateSeconds
                line = (.combatToLost, nearest(to: frame.targetPositions[target]))
            case (.alert, .combat):
                line = (.alertToCombat, detector)
            case (.lost, .combat):
                line = (.lostToCombat, detector)
            case (.alert, .normal):
                line = (.alertToNormal, formerMember(of: group))
            case (.lost, .normal):
                line = (.lostToNormal, formerMember(of: group))
            case (.combat, .normal) where frame.deadTargets.contains(target):
                line = (.combatToNormal, formerMember(of: group))
            default:
                line = nil
            }
            guard let line, let speaker = line.speaker else { return }
            speak((line.subtype, speaker), group: &group, random: &random, say: say)
        }

        /// A member that detects the target again.
        private var detector: ReferenceKey? {
            members.first { !$0.isSearching && $0.canSpeak }?.key
        }

        private func nearest(to point: SIMD3<Float>?) -> ReferenceKey? {
            let speakers = members.filter(\.canSpeak)
            guard let point else { return speakers.first?.key }
            return speakers.min {
                simd_distance_squared($0.feet, point) < simd_distance_squared($1.feet, point)
            }?.key
        }

        /// The member of the group that was nearest the target's place, or else the player.
        private func formerMember(of group: DetectionDialogueState.Group) -> ReferenceKey? {
            let point = frame.targetPositions[target] ?? frame.playerFeet
            return group.members.sorted { $0.key < $1.key }.min {
                simd_distance_squared($0.value, point) < simd_distance_squared($1.value, point)
            }?.key
        }

        private func speak(
            _ line: (subtype: DetectionSubtype, speaker: ReferenceKey),
            group: inout DetectionDialogueState.Group,
            random: inout ConditionRandom,
            say: (DetectionLineRequest) -> Bool
        ) {
            let (subtype, speaker) = line
            guard frame.now >= group.readyAt[subtype] ?? 0 else { return }
            let request = DetectionLineRequest(subtype: subtype, speaker: speaker, about: target)
            guard say(request) else { return }
            let range = subtype.isIdle ? idleWait : DetectionDialogueCore.changeWait
            group.readyAt[subtype] = frame.now + DetectionDialogueCore.roll(range, &random)
        }
    }
}
