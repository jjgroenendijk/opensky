// User-facing playback categories authored by vanilla SNCT records. These are
// the four nodes carrying SNCT.FNAM `Should Appear on Menu`; the separate
// `_AudioCategoryMaster` node remains WorldAudioEngine.masterVolume.

nonisolated public enum AudioCategory: String, CaseIterable, Sendable {
    case effects
    case voice
    case music
    case footsteps

    /// Vanilla SNCT.EDID used when resolving a SNDR.GNAM parent chain.
    public var soundCategoryEditorID: String {
        switch self {
        case .effects: "AudioCategorySFX"
        case .voice: "AudioCategoryVOCGeneral"
        case .music: "AudioCategoryMUS"
        case .footsteps: "AudioCategoryFST"
        }
    }

    /// SNCT.FULL's English labels, without the translation `$` marker.
    public var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// Accessibility-identifier fragment (`Audio<Category>VolumeControl`).
    public var identifierFragment: String {
        displayName
    }

    public init?(soundCategoryEditorID: String?) {
        guard let wanted = soundCategoryEditorID?.lowercased() else { return nil }
        guard
            let category = Self.allCases.first(where: {
                $0.soundCategoryEditorID.lowercased() == wanted
            }) else { return nil }
        self = category
    }
}
