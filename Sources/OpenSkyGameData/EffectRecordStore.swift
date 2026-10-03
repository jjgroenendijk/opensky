// The load-order records of visual and audio effects: image spaces and their
// modifiers, effect shaders, visual effects, addon nodes, explosions, debris,
// precipitation geometry, volumetric lighting, material objects, output models,
// reverbs, and art objects. Built once off one `RecordIndex`. See docs/formats/image-spaces.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct EffectRecordStore: Sendable {
    public static let recordTypes: Set<FourCC> = [
        "IMGS", "IMAD", "EFSH", "RFCT", "ADDN", "EXPL", "DEBR", "SPGD", "VOLI", "MATO",
        "SOPM", "REVB", "ARTO", "HAZD", "SNDR", "LIGH", "IPDS", "PROJ", "SPEL", "ENCH",
        "ACTI", "STAT", "MSTT", "TREE", "FURN", "MISC", "LVLI"
    ]

    public let imageSpaces: TypedRecordStore<ImageSpace>
    public let imageSpaceAdapters: TypedRecordStore<ImageSpaceAdapter>
    public let effectShaders: TypedRecordStore<EffectShader>
    public let visualEffects: TypedRecordStore<VisualEffect>
    public let addonNodes: TypedRecordStore<AddonNode>
    public let explosions: TypedRecordStore<Explosion>
    public let debris: TypedRecordStore<Debris>
    public let shaderParticles: TypedRecordStore<ShaderParticleGeometry>
    public let volumetricLighting: TypedRecordStore<VolumetricLighting>
    public let materialObjects: TypedRecordStore<MaterialObject>
    public let outputModels: TypedRecordStore<SoundOutputModel>
    public let reverbs: TypedRecordStore<ReverbParameters>
    public let artObjects: TypedRecordStore<ArtObject>

    public init(index: RecordIndex) {
        imageSpaces = Self.store(index, "IMGS") { try ImageSpace(record: $0.record) }
        imageSpaceAdapters = Self.store(index, "IMAD") {
            try ImageSpaceAdapter(record: $0.record)
        }
        effectShaders = Self.store(index, "EFSH") { try EffectShader(record: $0.record) }
        visualEffects = Self.store(index, "RFCT") { try VisualEffect(record: $0.record) }
        addonNodes = Self.store(index, "ADDN") { try AddonNode(record: $0.record) }
        explosions = Self.store(index, "EXPL") {
            try Explosion(record: $0.record, localized: $0.localized)
        }
        debris = Self.store(index, "DEBR") { try Debris(record: $0.record) }
        shaderParticles = Self.store(index, "SPGD") {
            try ShaderParticleGeometry(record: $0.record)
        }
        volumetricLighting = Self.store(index, "VOLI") {
            try VolumetricLighting(record: $0.record)
        }
        materialObjects = Self.store(index, "MATO") { try MaterialObject(record: $0.record) }
        outputModels = Self.store(index, "SOPM") { try SoundOutputModel(record: $0.record) }
        reverbs = Self.store(index, "REVB") { try ReverbParameters(record: $0.record) }
        artObjects = Self.store(index, "ARTO") { try ArtObject(record: $0.record) }
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: Self.recordTypes))
    }

    /// An empty store, for a synthetic scene.
    public static let empty = EffectRecordStore(plugins: [])

    /// The identity a link written in `plugin` names, or nil for a null link.
    public func resolve(_ id: FormID?, fromPlugin plugin: String) -> ReferenceKey? {
        imageSpaces.index.resolvedID(id, fromPlugin: plugin).map { ReferenceKey(resolved: $0) }
    }

    /// The identity a link inside `record` names.
    public func resolve(_ id: FormID?, from record: ResolvedRecord<some Any>) -> ReferenceKey? {
        resolve(id, fromPlugin: record.sourcePlugin)
    }

    /// The record type behind `key`, or nil when no indexed record has it.
    public func recordType(_ key: ReferenceKey) -> FourCC? {
        guard
            case let .plugin(name, objectID) = key,
            case let .record(indexed) = imageSpaces.index.lookup(
                ResolvedFormID(plugin: name, objectID: objectID)
            )
        else { return nil }
        return indexed.record.type
    }

    private static func store<Record: Sendable & EditorIdentified>(
        _ index: RecordIndex,
        _ type: FourCC,
        decode: (IndexedRecord) throws -> Record
    ) -> TypedRecordStore<Record> {
        TypedRecordStore(index: index, types: [type], decode: decode, editorID: \.editorID)
    }
}

/// A decoded record with an `EDID`.
nonisolated public protocol EditorIdentified {
    var editorID: String? { get }
}

nonisolated extension ImageSpace: EditorIdentified {}
nonisolated extension ImageSpaceAdapter: EditorIdentified {}
nonisolated extension EffectShader: EditorIdentified {}
nonisolated extension VisualEffect: EditorIdentified {}
nonisolated extension AddonNode: EditorIdentified {}
nonisolated extension Explosion: EditorIdentified {}
nonisolated extension Debris: EditorIdentified {}
nonisolated extension ShaderParticleGeometry: EditorIdentified {}
nonisolated extension VolumetricLighting: EditorIdentified {}
nonisolated extension MaterialObject: EditorIdentified {}
nonisolated extension SoundOutputModel: EditorIdentified {}
nonisolated extension ReverbParameters: EditorIdentified {}
nonisolated extension ArtObject: EditorIdentified {}

nonisolated extension TypedRecordStore {
    /// The record a load-order identity names.
    public func record(_ key: ReferenceKey) -> ResolvedRecord<Record>? {
        guard case let .plugin(name, objectID) = key else { return nil }
        return record(ResolvedFormID(plugin: name, objectID: objectID))
    }
}
