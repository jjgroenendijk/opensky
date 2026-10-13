// What the install's `.hkx` files hold for `openskycli gaps`: Havok classes by objects,
// clip annotation events by clips, and behaviour graph variables by graphs. Which
// classes a decoder reads is decided here; events and variables, by the engine.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct HKXGapCensus: Sendable {
    /// Havok class name -> objects.
    public private(set) var classes = GapCounts()
    /// Annotation event, payload folded to `.*` -> clips that carry it.
    public private(set) var annotations = GapCounts()
    /// Variable name -> behaviour graphs that declare it.
    public private(set) var graphVariables = GapCounts()
    /// Failure kind -> files.
    public private(set) var failures = GapCounts()
    public private(set) var fileCount = 0

    public init() {}

    /// Classes some decoder reads: the behaviour node classes, the graph-level
    /// classes, and the animation and skeleton classes. The animation container is
    /// read through its animations and bindings.
    public static let decoded: Set<String> = Set(HKBClassRegistry.decoders.keys)
        .union(HKBClassRegistry.graphLevelClassNames)
        .union([
            HKBRootLevelContainer.className, HKBProjectData.className,
            HKBCharacterData.className, HKASkeleton.className,
            HKASplineCompressedAnimation.className, HKAAnimationBinding.className,
            "hkaAnimationContainer"
        ])

    public mutating func record(data: Data) {
        fileCount += 1
        do {
            let graph = try HKXObjectGraph.decode(data)
            let names = graph.objectRefs.map { $0.className ?? "object with no class name" }
            for name in names {
                classes.add(name)
            }
            if names.contains(HKASplineCompressedAnimation.className) {
                try recordAnnotations(graph)
            }
            if names.contains(HKBBehaviorGraph.className), !HKXObjectGraph.isTagfile(data) {
                let census = try HKBBehaviorCensus.census(of: HKXFile(data: data))
                for name in Set(census.variables.compactMap(\.name)) {
                    graphVariables.add(name)
                }
            }
        } catch {
            failures.add("file does not decode: " + GapCounts.failureKind("\(error)"))
        }
    }

    private mutating func recordAnnotations(_ graph: HKXObjectGraph) throws {
        for clip in try HKASplineCompressedAnimation.animations(in: graph) {
            for event in Set(clip.annotations.map { Self.event($0.text) }) {
                annotations.add(event)
            }
        }
    }

    /// `SoundPlay.NPCFootstep` and `PIE@SGVF|x` keep only their event part.
    static func event(_ text: String) -> String {
        guard let cut = text.firstIndex(where: { $0 == "." || $0 == "@" }) else { return text }
        return text[..<cut] + ".*"
    }
}
