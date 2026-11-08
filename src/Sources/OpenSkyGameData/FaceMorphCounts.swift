// How many brow, eye, lip, and nose types the race menu may offer, from the game
// settings, and a check of those counts against the face data.
// See docs/engine/race-menu.md.

import Foundation

nonisolated public struct FaceMorphCounts: Equatable, Sendable {
    /// One type group: its setting, its chargen TRI target prefix, and its `NAMA` index.
    nonisolated public struct Group: Equatable, Sendable {
        public let setting: String
        public let targetPrefix: String
        public let partIndex: Int
    }

    public static let groups = [
        Group(setting: "iNoseMorphCount", targetPrefix: "NoseType", partIndex: 0),
        Group(setting: "iEyeMorphCount", targetPrefix: "EyesType", partIndex: 2),
        Group(setting: "iLipMorphCount", targetPrefix: "LipType", partIndex: 3)
    ]

    /// `iBrowMorphCount`; the brow types are not chargen TRI targets.
    public var brow = 20
    /// `iEyeMorphCount`, `iLipMorphCount`, and `iNoseMorphCount`; type 0 is the base shape.
    public var eye = 38
    public var lip = 31
    public var nose = 31

    public static let vanilla = Self()

    public init() {}

    /// The setting's count for a `NAMA` index, or nil for an index without a type group.
    public func count(partIndex: Int) -> Int? {
        switch partIndex {
        case 0: nose
        case 2: eye
        case 3: lip
        default: nil
        }
    }

    /// One line per group whose count differs from the types the chargen TRI holds: the
    /// base type 0 plus every numbered target in `targetNames`.
    public func mismatches(targetNames: [String]) -> [String] {
        Self.groups.compactMap { group in
            guard let count = count(partIndex: group.partIndex) else { return nil }
            let held = Self.highestType(group.targetPrefix, in: targetNames) + 1
            return held == count ? nil : "\(group.setting) \(count), chargen TRI holds \(held)"
        }
    }

    /// The highest `n` among targets named `<prefix><n>`, or 0 when there is none.
    public static func highestType(_ prefix: String, in names: [String]) -> Int {
        names.compactMap { name -> Int? in
            guard name.hasPrefix(prefix) else { return nil }
            return Int(name.dropFirst(prefix.count))
        }.max() ?? 0
    }

    public static func resolve(store: GameSettingStore) -> Self {
        var counts = vanilla
        store.read("iBrowMorphCount", into: &counts, \.brow)
        store.read("iEyeMorphCount", into: &counts, \.eye)
        store.read("iLipMorphCount", into: &counts, \.lip)
        store.read("iNoseMorphCount", into: &counts, \.nose)
        return counts
    }
}
