// What one `.hkt` tagfile holds: class definitions with versions, objects per
// class, cloth classes, and skeleton bones. Counts and names only.
// See docs/formats/hkt-tagfile.md.

import Foundation

nonisolated public struct HKTCensus: Equatable, Sendable {
    /// A class name and the version the file declares for it.
    public struct ClassVersion: Hashable, Comparable, Sendable {
        public let name: String
        public let version: Int

        public static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.name, lhs.version) < (rhs.name, rhs.version)
        }
    }

    public let version: Int
    public let hasEndTag: Bool
    public let definitions: [ClassVersion]
    /// Objects per class name, nested ones included.
    public let objectCounts: [String: Int]
    /// Classes of the Havok cloth family (`hcl` prefix or a `Cloth` name).
    public let clothClasses: [String]
    /// Bone names of every `hkaSkeleton` the file holds, in file order.
    public let skeletonBones: [String]

    public init(file: HKTagfile) {
        version = file.version
        hasEndTag = file.hasEndTag
        definitions = file.classes.dropFirst()
            .map { ClassVersion(name: $0.name, version: $0.version) }
        var counts: [String: Int] = [:]
        var bones: [String] = []
        for object in file.objects {
            let name = file.className(of: object)
            counts[name, default: 0] += 1
            if name == "hkaSkeleton", case let .array(entries)? = object["bones"] {
                bones += entries.compactMap(Self.boneName)
            }
        }
        objectCounts = counts
        clothClasses = definitions.map(\.name)
            .filter { $0.hasPrefix("hcl") || $0.localizedCaseInsensitiveContains("cloth") }
        skeletonBones = bones
    }

    public var objectCount: Int {
        objectCounts.values.reduce(0, +)
    }

    private static func boneName(_ value: HKTValue) -> String? {
        guard case let .structure(fields) = value, case let .string(name)? = fields["name"] else {
            return nil
        }
        return name
    }
}
