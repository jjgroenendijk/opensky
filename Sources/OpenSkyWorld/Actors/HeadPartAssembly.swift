// The head parts an actor shows when its head is assembled instead of baked:
// race defaults, NPC overrides by part type, extra parts, and the race filter.
// Rules and sources: docs/formats/head-parts.md, "Assembly".

import Foundation
import OpenSkyFormatsESM

nonisolated public enum HeadPartOrigin: Equatable, Sendable {
    case raceDefault
    case npcOverride
    /// Came along through another part's HNAM list.
    case extraPart
}

nonisolated public struct ResolvedHeadPart: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let partType: HeadPart.PartType?
    public let origin: HeadPartOrigin
    /// Relative to `Data/meshes`.
    public let modelPath: String
    /// TNAM texture set paths, relative to `Data/textures`; nil keeps the mesh's own.
    public let diffuseTexture: String?
    public let normalTexture: String?
    /// HCLF for hair, facial hair, and brows, else the part's CNAM; 0...1.
    public let tint: SIMD3<Float>?
}

nonisolated public struct HeadPartMiss: Equatable, Sendable {
    nonisolated public enum Reason: Equatable, Sendable {
        case missingRecord
        /// RNAM names a race list without the actor's race.
        case wrongRace
        case noModel
        /// An HNAM list leads back to a part already taken.
        case cycle
    }

    public let formID: FormID
    public let reason: Reason
}

nonisolated public struct HeadPartSet: Equatable, Sendable {
    public let parts: [ResolvedHeadPart]
    public let misses: [HeadPartMiss]
}

/// Pure over raw-FormID tables of one plugin, like `ActorVisualResolver`.
nonisolated public struct HeadPartResolver: Sendable {
    public let headParts: [UInt32: HeadPart]
    public let formLists: [UInt32: FormList]
    public let textureSets: [UInt32: TextureSet]
    public let colors: [UInt32: ColorForm]

    public init(
        headParts: [UInt32: HeadPart],
        formLists: [UInt32: FormList] = [:],
        textureSets: [UInt32: TextureSet] = [:],
        colors: [UInt32: ColorForm] = [:]
    ) {
        self.headParts = headParts
        self.formLists = formLists
        self.textureSets = textureSets
        self.colors = colors
    }

    private static let hairColored: Set<HeadPart.PartType> = [.hair, .facialHair, .eyebrows]

    /// An NPC part replaces the race default of its type; misc parts add up.
    public func resolve(
        raceDefaults: [FormID],
        npcParts: [FormID],
        race: FormID,
        hairColor: FormID?
    ) -> HeadPartSet {
        var misses: [HeadPartMiss] = []
        var chosen: [(HeadPart, HeadPartOrigin)] = []
        for id in raceDefaults {
            if let part = accepted(id, race: race, misses: &misses) {
                chosen.append((part, .raceDefault))
            }
        }
        for id in npcParts {
            guard let part = accepted(id, race: race, misses: &misses) else { continue }
            if let type = part.partType, type != .misc {
                chosen.removeAll { $0.0.partType == type }
            }
            chosen.append((part, .npcOverride))
        }
        var result = Accumulator(misses: misses)
        for (part, origin) in chosen {
            expand(part, origin: origin, race: race, hairColor: hairColor, into: &result)
        }
        return HeadPartSet(parts: result.parts, misses: result.misses)
    }

    private struct Accumulator {
        var taken = Set<UInt32>()
        var parts: [ResolvedHeadPart] = []
        var misses: [HeadPartMiss]
    }

    private func accepted(
        _ id: FormID,
        race: FormID,
        misses: inout [HeadPartMiss]
    ) -> HeadPart? {
        guard let part = headParts[id.rawValue] else {
            misses.append(HeadPartMiss(formID: id, reason: .missingRecord))
            return nil
        }
        if
            let list = part.validRaces.flatMap({ formLists[$0.rawValue] }),
            !list.entries.contains(race)
        {
            misses.append(HeadPartMiss(formID: id, reason: .wrongRace))
            return nil
        }
        return part
    }

    /// Recursion depth is bounded by `taken`: each part enters once.
    private func expand(
        _ part: HeadPart,
        origin: HeadPartOrigin,
        race: FormID,
        hairColor: FormID?,
        into result: inout Accumulator
    ) {
        guard result.taken.insert(part.formID.rawValue).inserted else {
            if origin == .extraPart {
                result.misses.append(HeadPartMiss(formID: part.formID, reason: .cycle))
            }
            return
        }
        if let path = part.model?.path, !path.isEmpty {
            result.parts.append(resolved(part, origin: origin, path: path, hairColor: hairColor))
        } else if part.extraParts.isEmpty {
            // A part without a mesh may only group its extra parts.
            result.misses.append(HeadPartMiss(formID: part.formID, reason: .noModel))
        }
        for extra in part.extraParts {
            guard let next = accepted(extra, race: race, misses: &result.misses) else { continue }
            expand(next, origin: .extraPart, race: race, hairColor: hairColor, into: &result)
        }
    }

    private func resolved(
        _ part: HeadPart,
        origin: HeadPartOrigin,
        path: String,
        hairColor: FormID?
    ) -> ResolvedHeadPart {
        let textures = part.textureSet.flatMap { textureSets[$0.rawValue] }
        let usesHairColor = part.partType.map(Self.hairColored.contains) ?? false
        let colorID = usesHairColor ? hairColor ?? part.color : part.color
        let tint = colorID.flatMap { colors[$0.rawValue]?.color }
            .map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) / 255 }
        return ResolvedHeadPart(
            formID: part.formID,
            editorID: part.editorID,
            partType: part.partType,
            origin: origin,
            modelPath: path,
            diffuseTexture: textures?.diffusePath,
            normalTexture: textures?.normalPath,
            tint: tint
        )
    }
}
