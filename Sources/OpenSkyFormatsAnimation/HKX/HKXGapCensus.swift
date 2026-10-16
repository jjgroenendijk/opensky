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
    /// Variable name -> how graphs use it: `Class.memberPath` for each binding,
    /// and `assignedUse` for an expression statement that assigns it.
    public private(set) var variableUses: [String: Set<String>] = [:]
    /// Failure kind -> files.
    public private(set) var failures = GapCounts()
    public private(set) var fileCount = 0

    public static let assignedUse = "expression assignment"

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
                recordVariableUses(graph, names: census.variables.map(\.name))
            }
        } catch {
            failures.add("file does not decode: " + GapCounts.failureKind("\(error)"))
        }
    }

    private mutating func recordVariableUses(_ graph: HKXObjectGraph, names: [String?]) {
        for ref in graph.objectRefs {
            let target = HKXPointerTarget(
                sectionIndex: ref.sectionIndex,
                dataOffset: ref.dataOffset
            )
            guard
                let className = ref.className,
                let object = HKBClassRegistry.decode(at: target, in: graph)
            else { continue }
            if let array = object as? HKBExpressionDataArray {
                for data in array.expressionsData {
                    if let name = data.expression.flatMap(Self.assignedVariable) {
                        variableUses[name, default: []].insert(Self.assignedUse)
                    }
                }
            }
            guard
                let reference = object.references
                    .first(where: { $0.field == "m_variableBindingSet" }),
                let set = HKBClassRegistry.decode(at: reference.target, in: graph)
                as? HKBVariableBindingSet
            else { continue }
            for binding in set.bindings where binding.bindingType == 0 {
                guard
                    names.indices.contains(binding.variableIndex),
                    let name = names[binding.variableIndex],
                    let path = binding.memberPath
                else { continue }
                let member = path.hasPrefix("m_") ? String(path.dropFirst(2)) : path
                variableUses[name, default: []].insert("\(className).\(member)")
            }
        }
    }

    /// The variable an expression statement such as `iState = 3` assigns, or nil
    /// for an event statement or a comparison.
    static func assignedVariable(_ text: String) -> String? {
        let characters = Array(text)
        for index in characters.indices where characters[index] == "=" {
            let next = index + 1 < characters.count ? characters[index + 1] : " "
            let previous = index > 0 ? characters[index - 1] : " "
            guard next != "=", !"!<>=".contains(previous) else { return nil }
            let name = String(characters[..<index]).trimmingCharacters(in: .whitespaces)
            let valid = !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
            return valid ? name : nil
        }
        return nil
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
