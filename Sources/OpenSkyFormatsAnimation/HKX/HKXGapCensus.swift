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
    /// Variables some graph gives a non-zero bool, integer, or real initial value.
    public private(set) var authoredVariables: Set<String> = []
    /// Which annotations the graphs of their own project wait for.
    public private(set) var hearing = HKXAnnotationHearing()
    /// Failure kind -> files.
    public private(set) var failures = GapCounts()
    public private(set) var fileCount = 0

    public static let assignedUse = "expression assignment"
    /// A condition or an expression reads the variable.
    public static let expressionReadUse = "expression read"
    /// A state machine writes its current state to its `m_syncVariableIndex`.
    public static let syncUse = "hkbStateMachine.syncVariable"

    public init() {}

    /// Classes some decoder reads: the behaviour node classes, the graph-level
    /// classes, and the animation and skeleton classes. The animation container is
    /// read through its animations and bindings.
    public static let decoded: Set<String> = Set(HKBClassRegistry.decoders.keys)
        .union(HKBClassRegistry.graphLevelClassNames)
        .union([
            HKBRootLevelContainer.className, HKBProjectData.className,
            HKBCharacterData.className, HKASkeleton.className,
            HKBProjectData.stringDataClassName, HKBCharacterData.stringDataClassName,
            HKASplineCompressedAnimation.className, HKAAnimationBinding.className,
            "hkaAnimationContainer"
        ])

    /// `path` places the file in its project, so an annotation meets its own graphs.
    public mutating func record(data: Data, path: String = "") {
        fileCount += 1
        do {
            let graph = try HKXObjectGraph.decode(data)
            let names = graph.objectRefs.map { $0.className ?? "object with no class name" }
            for name in names {
                classes.add(name)
            }
            if names.contains(HKASplineCompressedAnimation.className) {
                try recordAnnotations(graph, path: path)
            }
            if names.contains(HKBBehaviorGraph.className), !HKXObjectGraph.isTagfile(data) {
                let census = try HKBBehaviorCensus.census(of: HKXFile(data: data))
                for name in Set(census.variables.compactMap(\.name)) {
                    graphVariables.add(name)
                }
                recordAuthoredValues(census.variables, graph: graph)
                recordGraphUses(
                    graph, variables: census.variables.map(\.name),
                    events: census.eventNames, path: path
                )
            }
        } catch {
            failures.add("file does not decode: " + GapCounts.failureKind("\(error)"))
        }
    }

    /// How the graph uses its variables, and which events it waits for.
    private mutating func recordGraphUses(
        _ graph: HKXObjectGraph, variables names: [String?], events: [String?], path: String
    ) {
        var listened: [String] = []
        defer { hearing.addListened(listened, graphPath: path) }
        let declared = Set(names.compactMap(\.self))
        for ref in graph.objectRefs {
            let target = HKXPointerTarget(
                sectionIndex: ref.sectionIndex,
                dataOffset: ref.dataOffset
            )
            guard
                let className = ref.className,
                let object = HKBClassRegistry.decode(at: target, in: graph)
            else { continue }
            listened += HKBEventListeners.eventIDs(of: object)
                .compactMap { events.indices.contains($0) ? events[$0] : nil }
            recordExpressionUses(object, declared: declared)
            if
                let machine = object as? HKBStateMachine,
                names.indices.contains(machine.syncVariableIndex),
                let name = names[machine.syncVariableIndex]
            {
                variableUses[name, default: []].insert(Self.syncUse)
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

    /// An assignment writes its left side; every other variable an expression or a
    /// condition names is read.
    private mutating func recordExpressionUses(_ object: any HKBClass, declared: Set<String>) {
        var texts: [String] = []
        if let array = object as? HKBExpressionDataArray {
            texts = array.expressionsData.compactMap(\.expression)
        } else if let condition = object as? HKBExpressionCondition {
            texts = condition.expression.map { [$0] } ?? []
        }
        for text in texts {
            let assigned = Self.assignedVariable(text)
            if let assigned {
                variableUses[assigned, default: []].insert(Self.assignedUse)
            }
            let read = Self.identifiers(in: text).intersection(declared)
            for name in read where name != assigned {
                variableUses[name, default: []].insert(Self.expressionReadUse)
            }
        }
    }

    /// The names in an expression: runs of letters, digits, and underscores.
    static func identifiers(in text: String) -> Set<String> {
        let parts = text.split { !($0.isLetter || $0.isNumber || $0 == "_") }
        return Set(parts.map(String.init))
    }

    /// Quad and pointer variables keep their values elsewhere, so only the word types count.
    private mutating func recordAuthoredValues(
        _ variables: [HKBCensusVariable], graph: HKXObjectGraph
    ) {
        let words = HKBBehaviorGraph.graphs(in: graph).first?.data?.variableInitialValues?
            .wordValues ?? []
        let wordTypes: Set<HKBVariableType> = [.bool, .int8, .int16, .int32, .real]
        for (index, variable) in variables.enumerated() {
            guard
                let name = variable.name, let type = variable.type, wordTypes.contains(type),
                words.indices.contains(index), words[index] != 0
            else { continue }
            authoredVariables.insert(name)
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

    private mutating func recordAnnotations(_ graph: HKXObjectGraph, path: String) throws {
        for clip in try HKASplineCompressedAnimation.animations(in: graph) {
            for event in Set(clip.annotations.map { Self.event($0.text) }) {
                annotations.add(event)
            }
            for annotation in clip.annotations {
                hearing.addAnnotation(annotation.text, clipPath: path)
            }
        }
    }

    /// `SoundPlay.NPCFootstep` and `PIE@SGVF|x` keep only their event part.
    static func event(_ text: String) -> String {
        guard let cut = text.firstIndex(where: { $0 == "." || $0 == "@" }) else { return text }
        return text[..<cut] + ".*"
    }
}
