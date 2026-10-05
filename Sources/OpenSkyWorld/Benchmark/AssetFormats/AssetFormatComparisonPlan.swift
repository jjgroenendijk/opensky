// The fixed sample of the asset format comparison: the same base-game files on
// every run (docs/tools/asset-format-comparison.md).

import Foundation

nonisolated public enum AssetKind: String, CaseIterable, Codable, Sendable {
    case texture
    case mesh
    case collision
    case animation
    case audio
}

/// How a texture is sampled. Each role has its own quality needs.
nonisolated public enum TextureRole: String, CaseIterable, Codable, Sendable {
    case color
    case normal
    case data
}

nonisolated public struct AssetSampleEntry: Codable, Equatable, Sendable {
    public let path: String
    public let kind: AssetKind
    /// Set for textures only.
    public let role: TextureRole?

    public init(path: String, kind: AssetKind, role: TextureRole? = nil) {
        self.path = path
        self.kind = kind
        self.role = role
    }

    static func texture(_ path: String, _ role: TextureRole) -> Self {
        Self(path: "textures\\" + path, kind: .texture, role: role)
    }

    static func meshes(_ path: String) -> [Self] {
        let full = "meshes\\" + path
        return [Self(path: full, kind: .mesh), Self(path: full, kind: .collision)]
    }
}

nonisolated public struct AssetFormatComparisonPlan: Codable, Equatable, Sendable {
    public let entries: [AssetSampleEntry]
    /// Loads per measured row; the row reports the run with the median total.
    public let repeats: Int

    public init(entries: [AssetSampleEntry], repeats: Int) {
        self.entries = entries
        self.repeats = repeats
    }

    public static let standard = Self(
        entries: standardTextures + standardModels + standardAnimations + standardAudio,
        repeats: 5
    )

    /// BC1, BC3, and 32-bit sources from 64 to 4096 texels across.
    static let standardTextures: [AssetSampleEntry] = [
        .texture("landscape\\dirt01.dds", .color),
        .texture("landscape\\mountains\\mountainslab01.dds", .color),
        .texture("architecture\\whiterun\\wrbrazier01.dds", .color),
        .texture("architecture\\whiterun\\naildecal.dds", .color),
        .texture("armor\\iron\\f\\cuirassplate.dds", .color),
        .texture("actors\\character\\male\\malebody_1.dds", .color),
        .texture("dlc01\\sky\\soulcairncloudsupper01.dds", .color),
        .texture("terrain\\tamriel\\tamriel.16.-16.-16.dds", .color),
        .texture("landscape\\dirt01_n.dds", .normal),
        .texture("landscape\\mountains\\mountainslab01_n.dds", .normal),
        .texture("architecture\\whiterun\\wrbrazier01_n.dds", .normal),
        .texture("armor\\iron\\f\\cuirassplate_n.dds", .normal),
        .texture("actors\\character\\male\\malehead_msn.dds", .normal),
        .texture("actors\\character\\male\\malebody_1_s.dds", .data),
        .texture("actors\\character\\male\\malebody_1_sk.dds", .data),
        .texture("weapons\\iron\\ironbattleaxe_em.dds", .data)
    ]

    /// Static models from small clutter to a building, each with collision.
    static let standardModels: [AssetSampleEntry] = [
        "clutter\\common\\pitchfork01.nif",
        "clutter\\common\\commontablethin01.nif",
        "clutter\\brewerycasklargeclosed01.nif",
        "landscape\\rocks\\rockcliff01.nif",
        "landscape\\trees\\treeaspen01.nif",
        "architecture\\whiterun\\wrbuildings\\wrhousestores01.nif"
    ].flatMap(AssetSampleEntry.meshes)

    static let standardAnimations: [AssetSampleEntry] = [
        "actors\\character\\animations\\1hm_idle.hkx",
        "actors\\character\\animations\\1hm_attackleft.hkx",
        "actors\\character\\animations\\1hm_1stp_run.hkx",
        "actors\\ambient\\chicken\\animations\\mt_idle.hkx"
    ].map { AssetSampleEntry(path: "meshes\\" + $0, kind: .animation) }

    /// Short WAV effects, a long xWMA music track, and a FUZ voice line.
    static let standardAudio: [AssetSampleEntry] = [
        "sound\\fx\\npc\\bear\\death\\npc_bear_death_02.wav",
        "sound\\fx\\fst\\npc\\dirt\\walk\\r\\fst_npc_dirt_walk_04.wav",
        "music\\explore\\forestfall\\palette\\day\\a\\mus_palette_forestfall_day_a_01.xwm",
        "sound\\voice\\skyrim.esm\\malenord\\bardscolle_bardscollegepoe_000e774d_1.fuz"
    ].map { AssetSampleEntry(path: $0, kind: .audio) }
}
