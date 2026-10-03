// The effect records the Effects panel can pick by name, with one-line
// details for its inspector. See docs/rendering/visual-effects.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering

nonisolated public enum EffectRecordKind: String, Equatable, Sendable, CaseIterable {
    case visualEffect = "Visual effect"
    case shader = "Effect shader"
    case addon = "Addon node"
    case art = "Art object"
    case volumetricLighting = "Volumetric lighting"
    case material = "Material object"
}

nonisolated public struct EffectCatalogEntry: Equatable, Sendable {
    public let name: String
    public let key: ReferenceKey
    public let kind: EffectRecordKind
}

nonisolated public struct EffectCatalog: Sendable {
    public static let empty = EffectCatalog(records: .empty)

    /// Sorted by name; a name two records share keeps the first kind's record.
    public let entries: [EffectCatalogEntry]
    private let byName: [String: EffectCatalogEntry]

    public init(records: EffectRecordStore) {
        let entries = Self.entries(records.visualEffects, .visualEffect)
            + Self.entries(records.effectShaders, .shader)
            + Self.entries(records.addonNodes, .addon)
            + Self.entries(records.artObjects, .art)
            + Self.entries(records.volumetricLighting, .volumetricLighting)
            + Self.entries(records.materialObjects, .material)
        var byName: [String: EffectCatalogEntry] = [:]
        for entry in entries where byName[entry.name] == nil {
            byName[entry.name] = entry
        }
        self.byName = byName
        self.entries = byName.values.sorted { $0.name < $1.name }
    }

    public func entry(named name: String) -> EffectCatalogEntry? {
        byName[name]
    }

    private static func entries(
        _ store: TypedRecordStore<some EditorIdentified>, _ kind: EffectRecordKind
    ) -> [EffectCatalogEntry] {
        store.records.compactMap { resolved in
            resolved.record.editorID.map {
                EffectCatalogEntry(name: $0, key: ReferenceKey(resolved: resolved.id), kind: kind)
            }
        }
    }
}

nonisolated extension EffectRecordStore {
    /// Short label-and-value lines for the inspector.
    public func details(of entry: EffectCatalogEntry) -> [String] {
        let kind = "Kind: \(entry.kind.rawValue)"
        switch entry.kind {
        case .visualEffect:
            guard let resolved = visualEffects.record(entry.key) else { return [kind] }
            return [
                kind,
                "Art: \(name(of: resolve(resolved.record.effectArt, from: resolved)))",
                "Shader: \(name(of: resolve(resolved.record.shader, from: resolved)))"
            ]
        case .shader:
            return [kind] + shaderDetails(entry.key)
        case .addon:
            let record = addonNodes.record(entry.key)?.record
            return [
                kind,
                "Model: \(record?.model?.path ?? "none")",
                "Particle cap: \(record?.masterParticleSystemCap.map(String.init) ?? "none")"
            ]
        case .art:
            return [kind, "Model: \(artObjects.record(entry.key)?.record.modelPath ?? "none")"]
        case .volumetricLighting:
            return [kind] + volumetricDetails(entry.key)
        case .material:
            return [kind] + materialDetails(entry.key)
        }
    }

    private func name(of key: ReferenceKey?) -> String {
        guard let key else { return "none" }
        return visualEffectSpec(key)?.name ?? key.description
    }

    private func shaderDetails(_ key: ReferenceKey) -> [String] {
        guard let shader = effectShaders.record(key)?.record else { return [] }
        guard let look = MembraneLook(shader: shader) else { return ["Membrane: none"] }
        return [
            "Fill: \(Self.color(look.fillColor))",
            "Edge: \(Self.color(look.edgeColor)), falloff \(Self.number(look.edgeFalloff))",
            "Hit length: \(Self.number(look.hitDuration)) s"
        ]
    }

    private func volumetricDetails(_ key: ReferenceKey) -> [String] {
        guard let record = volumetricLighting.record(key)?.record else { return [] }
        return [
            "Intensity: \(record.intensity.map(Self.number) ?? "none")",
            "Color: \(record.color.map(Self.color) ?? "none")",
            "Density: \(record.densityContribution.map(Self.number) ?? "none")"
        ]
    }

    private func materialDetails(_ key: ReferenceKey) -> [String] {
        guard let record = materialObjects.record(key)?.record else { return [] }
        let snow = record.properties?.isSnow == true ? ", snow" : ""
        return [
            "Model: \(record.model?.path ?? "none")",
            "Falloff: \(record.properties.map { Self.number($0.falloffScale) } ?? "none")\(snow)"
        ]
    }

    static func number(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

    static func color(_ value: SIMD3<Float>) -> String {
        "\(number(value.x)) \(number(value.y)) \(number(value.z))"
    }
}
