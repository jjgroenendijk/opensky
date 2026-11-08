// Blender dump for `openskycli hkx --blenders`: each blender's flags, the variable
// bound to its blend parameter, and each child's weight and generator.

import Foundation
import OpenSkyFormatsAnimation

enum HKXBlenderDump {
    static func print(file: HKXFile) throws {
        let graph = try HKXObjectGraph(file: file)
        let variables = HKXBindingNames(file: file)
        for ref in graph.objectRefs {
            let target = HKXPointerTarget(
                sectionIndex: ref.sectionIndex,
                dataOffset: ref.dataOffset
            )
            guard let object = HKBClassRegistry.decode(at: target, in: graph) else { continue }
            if let cyclic = object as? BSCyclicBlendTransitionGenerator {
                let bindings = boundMembers(of: object, in: graph, variables: variables)
                Swift.print("\(object.className) \"\(object.nodeName ?? "")\""
                    + " parameter \(cyclic.blendParameter) \(bindings) -> "
                    + describeGenerator(cyclic.blenderGenerator, in: graph))
                continue
            }
            let fields: HKBBlenderFields
            switch object {
            case let blender as HKBBlenderGenerator: fields = blender.blender
            case let matching as HKBPoseMatchingGenerator: fields = matching.blender
            default: continue
            }
            let bindings = boundMembers(of: object, in: graph, variables: variables)
            Swift.print("\(object.className) \"\(object.nodeName ?? "")\" flags \(fields.flags)"
                + " parameter \(fields.blendParameter)"
                + " cyclic \(fields.minCyclicBlendParameter)...\(fields.maxCyclicBlendParameter)"
                + " master \(fields.indexOfSyncMasterChild) \(bindings)")
            for (index, childTarget) in fields.children.enumerated() {
                Swift.print("  [\(index)] " + describeChild(
                    childTarget,
                    in: graph,
                    variables: variables
                ))
            }
        }
    }

    /// `Class "node" member=variable` for each binding whose variable contains `text`.
    static func printBindings(file: HKXFile, containing text: String) throws {
        let graph = try HKXObjectGraph(file: file)
        let variables = HKXBindingNames(file: file)
        let wanted = text.lowercased()
        for ref in graph.objectRefs {
            let target = HKXPointerTarget(
                sectionIndex: ref.sectionIndex,
                dataOffset: ref.dataOffset
            )
            guard let object = HKBClassRegistry.decode(at: target, in: graph) else { continue }
            let bound = boundMembers(of: object, in: graph, variables: variables)
                .split(separator: " ")
                .filter { $0.split(separator: "=").last?.lowercased().contains(wanted) == true }
            guard !bound.isEmpty else { continue }
            Swift.print("\(object.className) \"\(object.nodeName ?? "")\" "
                + bound.joined(separator: " "))
        }
    }

    private static func describeChild(
        _ target: HKXPointerTarget?, in graph: HKXObjectGraph, variables: HKXBindingNames
    ) -> String {
        guard
            let target,
            let child = HKBClassRegistry.decode(at: target, in: graph) as? HKBBlenderGeneratorChild
        else { return "<missing>" }
        let bindings = boundMembers(of: child, in: graph, variables: variables)
        return "weight \(child.weight) \(bindings) -> "
            + describeGenerator(child.generator, in: graph)
    }

    private static func describeGenerator(_ target: HKXPointerTarget?, in graph: HKXObjectGraph)
        -> String
    {
        guard let target, let object = HKBClassRegistry.decode(at: target, in: graph) else {
            return "<none>"
        }
        let name = object.nodeName.map { " \"\($0)\"" } ?? ""
        if let clip = object as? HKBClipGenerator {
            return "clip\(name) \(clip.animationName ?? "?") mode \(clip.mode)"
        }
        return object.className + name
    }

    /// `member=variable` for each variable binding on `object`.
    private static func boundMembers(
        of object: any HKBClass, in graph: HKXObjectGraph, variables: HKXBindingNames
    ) -> String {
        guard
            let reference = object.references.first(where: { $0.field == "m_variableBindingSet" }),
            let set = HKBClassRegistry.decode(at: reference.target, in: graph)
            as? HKBVariableBindingSet
        else { return "" }
        return set.bindings.map { binding in
            "\(binding.memberPath ?? "?")=\(variables.name(of: binding))"
        }.joined(separator: " ")
    }
}

/// The names a binding can point at: a graph variable, or with binding type 1 a
/// character property, shown as `character:<name>`.
struct HKXBindingNames {
    let variables: [String?]
    let properties: [String?]

    init(file: HKXFile) {
        let census = try? HKBBehaviorCensus.census(of: file)
        variables = census?.variables.map(\.name) ?? []
        properties = census?.characterPropertyNames ?? []
    }

    func name(of binding: HKBVariableBinding) -> String {
        let isProperty = binding.bindingType == 1
        let names = isProperty ? properties : variables
        let index = binding.variableIndex
        let name = names.indices.contains(index) ? names[index] ?? "?" : "#\(index)"
        return isProperty ? "character:" + name : name
    }
}
