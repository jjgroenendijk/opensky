// Behavior-file census (todo 14.1): the one-pass summary of what a Havok
// packfile declares, shared by the env-gated sweep over the real install and
// by `openskycli hkx`. It answers the questions item 14.2 needs answered
// before node classes are written — which classes actually appear in the
// vanilla player graph, which variables and events the graph exposes, and
// which other files a project or character pulls in.
//
// The role is read from the root object's named variants, never from the
// filename and never from the container header's root class (every behavior,
// character, and project file declares the same `hkRootLevelContainer` root).
// Nothing is evaluated: this is inventory, not runtime.

import Foundation

/// What one packfile is, decided from the classes its root container names.
nonisolated enum HKBFileRole: String, Equatable, Sendable {
    /// Root of one behavior set: names the behavior, character, and animation
    /// directories (`defaultmale.hkx`, `firstperson.hkx`).
    case project
    /// Binds a behavior file to a rig and to the clips its graph may play.
    case character
    /// Holds one `hkbBehaviorGraph` and its node tree.
    case behavior
    /// An `hkaAnimationContainer` carrying skeletons but no animation.
    case skeleton
    /// An `hkaAnimationContainer` carrying animation clips.
    case animation
    /// A root container whose variants match none of the above.
    case unknown
}

/// One declared graph variable: its name, its declared type, and the raw byte
/// behind the type so an unrecognised value stays reportable.
nonisolated struct HKBCensusVariable: Equatable {
    let name: String?
    let type: HKBVariableType?
    let rawType: Int
}

/// Everything the census reports about one packfile. Counts, names, and paths
/// only — no sample data, no geometry, nothing that could carry game content
/// into the repository.
nonisolated struct HKBBehaviorCensus: Equatable {
    let role: HKBFileRole
    /// Class names of the root container's named variants, in file order.
    let rootVariantClassNames: [String]
    let objectCount: Int
    /// Class-name signature of the file: how many objects of each class.
    let classCounts: [String: Int]
    /// `hkbBehaviorGraph::m_name`, for a behavior file.
    let graphName: String?
    /// Class name of the graph's root generator — the first node class item
    /// 14.2 must decode for this file.
    let rootGeneratorClassName: String?
    let variables: [HKBCensusVariable]
    let eventNames: [String?]
    let characterPropertyNames: [String?]
    /// Behavior files this project or character references by name.
    let referencedBehaviorFiles: [String]
    /// Character files a project references by name.
    let referencedCharacterFiles: [String]
    /// Animation clips or clip directories this project or character
    /// references by name.
    let referencedAnimationFiles: [String]
    /// The animation, behavior, and character directories a project file
    /// declares, in that order; empty for every other role. Every vanilla
    /// project file leaves all three as empty strings and names its character
    /// file instead, so paths are relative to the project file's own folder.
    let contentPaths: [String]
    let unresolved: [HKXUnresolvedReference]

    var variableNames: [String] {
        variables.compactMap(\.name)
    }

    /// Class names in report order: most frequent first, ties alphabetical.
    var classCountsByFrequency: [(name: String, count: Int)] {
        classCounts
            .map { (name: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }

    /// Builds the census for an already-parsed packfile. Never throws: a file
    /// whose root container is missing or whose fields do not resolve comes
    /// back with `role == .unknown` and its misses listed, because the sweep's
    /// job is to report such a file, not to fail on it.
    static func census(of file: HKXFile) throws -> HKBBehaviorCensus {
        let graph = try HKXObjectGraph(file: file)
        let objects = file.objects
        var counts: [String: Int] = [:]
        for object in objects {
            counts[object.className ?? "<unresolved>", default: 0] += 1
        }
        guard let root = HKBRootLevelContainer.root(in: graph) else {
            return empty(objectCount: objects.count, classCounts: counts)
        }
        let variantClassNames = root.variants.compactMap(\.className)
        let content = decodeContent(root: root, graph: graph)
        return HKBBehaviorCensus(
            role: role(variantClassNames: variantClassNames, classCounts: counts),
            rootVariantClassNames: variantClassNames,
            objectCount: objects.count,
            classCounts: counts,
            graphName: content.behavior?.name,
            rootGeneratorClassName: content.behavior?.rootGeneratorClassName,
            variables: variables(of: content.behavior),
            eventNames: content.behavior?.data?.stringData?.eventNames
                ?? content.project?.eventNames ?? [],
            characterPropertyNames: content.behavior?.data?.stringData?
                .characterPropertyNames
                ?? content.character?.characterPropertyNames ?? [],
            referencedBehaviorFiles: referencedBehaviorFiles(content),
            referencedCharacterFiles: content.project?.characterFilenames
                .compactMap(\.self) ?? [],
            referencedAnimationFiles: referencedAnimationFiles(content),
            contentPaths: [
                content.project?.animationPath,
                content.project?.behaviorPath,
                content.project?.characterPath
            ].compactMap(\.self),
            unresolved: root.unresolved + content.unresolved
        )
    }

    // MARK: - Root variant decoding

    private struct Content {
        var behavior: HKBBehaviorGraph?
        var project: HKBProjectData?
        var character: HKBCharacterData?
        var unresolved: [HKXUnresolvedReference] = []
    }

    private static func decodeContent(
        root: HKBRootLevelContainer,
        graph: HKXObjectGraph
    ) -> Content {
        var content = Content()
        for variant in root.variants {
            guard let target = variant.variant else { continue }
            switch variant.className {
            case HKBBehaviorGraph.className:
                content.behavior = HKBBehaviorGraph.decode(at: target, in: graph)
                content.unresolved += content.behavior?.unresolved ?? []
            case HKBProjectData.className:
                content.project = HKBProjectData.decode(at: target, in: graph)
                content.unresolved += content.project?.unresolved ?? []
            case HKBCharacterData.className:
                content.character = HKBCharacterData.decode(at: target, in: graph)
                content.unresolved += content.character?.unresolved ?? []
            default:
                continue
            }
        }
        return content
    }

    private static func variables(of behavior: HKBBehaviorGraph?) -> [HKBCensusVariable] {
        guard let data = behavior?.data else { return [] }
        let names = data.stringData?.variableNames ?? []
        let infos = data.variableInfos
        // The two lists are parallel in a well-formed graph; a mismatched file
        // still reports every entry either list has, with the missing half nil.
        return (0 ..< max(names.count, infos.count)).map { index in
            HKBCensusVariable(
                name: index < names.count ? names[index] : nil,
                type: index < infos.count ? infos[index].type : nil,
                rawType: index < infos.count ? infos[index].rawType : -1
            )
        }
    }

    private static func referencedBehaviorFiles(_ content: Content) -> [String] {
        var names = content.project?.behaviorFilenames.compactMap(\.self) ?? []
        if let behaviorFilename = content.character?.behaviorFilename {
            names.append(behaviorFilename)
        }
        return names
    }

    private static func referencedAnimationFiles(_ content: Content) -> [String] {
        var names = content.project?.animationFilenames.compactMap(\.self) ?? []
        names += content.character?.animationNames.compactMap(\.self) ?? []
        return names
    }

    // MARK: - Role

    /// A project or character variant decides the role outright. Behavior
    /// files declare an `hkbBehaviorGraph` variant. Everything else is an
    /// animation container, split by whether the file carries clips.
    private static func role(
        variantClassNames: [String],
        classCounts: [String: Int]
    ) -> HKBFileRole {
        if variantClassNames.contains(HKBProjectData.className) {
            return .project
        }
        if variantClassNames.contains(HKBCharacterData.className) {
            return .character
        }
        if variantClassNames.contains(HKBBehaviorGraph.className) {
            return .behavior
        }
        guard variantClassNames.contains("hkaAnimationContainer") else { return .unknown }
        let hasAnimation = classCounts[HKAAnimationBinding.className] != nil
            || classCounts[HKASplineCompressedAnimation.className] != nil
        return hasAnimation ? .animation : .skeleton
    }

    private static func empty(
        objectCount: Int,
        classCounts: [String: Int]
    ) -> HKBBehaviorCensus {
        HKBBehaviorCensus(
            role: .unknown,
            rootVariantClassNames: [],
            objectCount: objectCount,
            classCounts: classCounts,
            graphName: nil,
            rootGeneratorClassName: nil,
            variables: [],
            eventNames: [],
            characterPropertyNames: [],
            referencedBehaviorFiles: [],
            referencedCharacterFiles: [],
            referencedAnimationFiles: [],
            contentPaths: [],
            unresolved: []
        )
    }
}
