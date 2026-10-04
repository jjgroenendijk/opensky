// Every player setting with its default and range. Vanilla rows keep the menu
// order measured with `openskycli swf system-menu`; a row no engine system reads
// yet is marked not applied. See docs/engine/settings.md.

import Foundation

nonisolated public struct PlayerSettingsCatalog: Sendable {
    public let definitions: [PlayerSettingDefinition]
    private let index: [PlayerSettingID: Int]

    public init(definitions: [PlayerSettingDefinition]) {
        self.definitions = definitions
        var index: [PlayerSettingID: Int] = [:]
        for (position, definition) in definitions.enumerated() where index[definition.id] == nil {
            index[definition.id] = position
        }
        self.index = index
    }

    public func definition(_ id: PlayerSettingID) -> PlayerSettingDefinition? {
        index[id].map { definitions[$0] }
    }

    public func definitions(in group: PlayerSettingGroup) -> [PlayerSettingDefinition] {
        definitions.filter { $0.group == group }
    }

    /// The menu-flagged `SNCT` categories the vanilla Audio page lists after Master.
    public static let audioCategoryEditorIDs = [
        ("AudioCategorySFX", "$Effects"), ("AudioCategoryFST", "$Footsteps"),
        ("AudioCategoryVOCGeneral", "$Voice"), ("AudioCategoryMUS", "$Music")
    ]

    /// Difficulty options in menu order. Level 2, Normal (Adept), is the default.
    public static let difficultyOptions = [
        "$Very Easy", "$Easy", "$Normal", "$Hard", "$Very Hard", "$Legendary"
    ]

    public static let saveOnPauseOptions = [
        "$5 Mins", "$10 Mins", "$15 Mins", "$30 Mins", "$45 Mins", "$60 Mins", "$Disabled"
    ]

    public static let vanilla = PlayerSettingsCatalog(
        definitions: gameplay + display + audio + opensky
    )

    private static let unit = PlayerSettingKind.slider(range: 0 ... 1, step: 0.05)

    private static func row(
        _ id: String, _ group: PlayerSettingGroup, _ kind: PlayerSettingKind,
        _ title: String, _ value: Double, applied: Bool = false
    ) -> PlayerSettingDefinition {
        PlayerSettingDefinition(
            id: PlayerSettingID(id), group: group, kind: kind, title: title,
            defaultValue: value, isApplied: applied
        )
    }

    private static let gameplay: [PlayerSettingDefinition] = [
        row("gameplay.invertY", .gameplay, .toggle, "$Invert Y", 0, applied: true),
        row("gameplay.lookSensitivity", .gameplay, unit, "$Look Sensitivity", 0.5, applied: true),
        row("gameplay.vibration", .gameplay, .toggle, "$Vibration", 1),
        row("gameplay.controller", .gameplay, .toggle, "$360 Controller", 0),
        row(
            "gameplay.missingCreationsCheck",
            .gameplay,
            .toggle,
            "$SaveGameMissingCreationsCheck",
            1
        ),
        row("gameplay.survivalMode", .gameplay, .toggle, "$Survival Mode", 0),
        row(
            "gameplay.difficulty",
            .gameplay,
            .choice(options: difficultyOptions),
            "$Difficulty",
            2,
            applied: true
        ),
        row(
            "gameplay.showFloatingMarkers",
            .gameplay,
            .toggle,
            "$Show Floating Markers",
            1,
            applied: true
        ),
        row("gameplay.saveOnRest", .gameplay, .toggle, "$Save on Rest", 1, applied: true),
        row("gameplay.saveOnWait", .gameplay, .toggle, "$Save on Wait", 1, applied: true),
        row("gameplay.saveOnTravel", .gameplay, .toggle, "$Save on Travel", 1, applied: true),
        row(
            "gameplay.saveOnPause",
            .gameplay,
            .choice(options: saveOnPauseOptions),
            "$Save on Pause",
            6,
            applied: true
        ),
        row("gameplay.useKinect", .gameplay, .toggle, "$Use Kinect Commands", 0)
    ]

    private static let display: [PlayerSettingDefinition] = [
        row("display.brightness", .display, unit, "$Brightness", 0.5),
        row("display.hudOpacity", .display, unit, "$HUD Opacity", 1, applied: true),
        row("display.actorFade", .display, unit, "$Actor Fade", 0.5),
        row("display.itemFade", .display, unit, "$Item Fade", 0.5),
        row("display.objectFade", .display, unit, "$Object Fade", 0.5),
        row("display.grassFade", .display, unit, "$Grass Fade", 0.5),
        row("display.shadowFade", .display, unit, "$Shadow Fade", 0.5),
        row("display.lightFade", .display, unit, "$Light Fade", 0.5),
        row("display.specularityFade", .display, unit, "$Specularity Fade", 0.5),
        row("display.treeLODFade", .display, unit, "$Tree LOD Fade", 0.5),
        row("display.crosshair", .display, .toggle, "$Crosshair", 1, applied: true),
        row("display.dialogueSubtitles", .display, .toggle, "$Dialogue Subtitles", 0),
        row("display.generalSubtitles", .display, .toggle, "$General Subtitles", 0),
        row("display.ddofIntensity", .display, unit, "$DDOF Intensity", 1)
    ]

    private static let audio: [PlayerSettingDefinition] =
        [row("audio.master", .audio, unit, "$Master", 1, applied: true)]
            + audioCategoryEditorIDs.map { editorID, title in
                row(
                    PlayerSettingID.categoryVolume(editorID).rawValue, .audio, unit, title, 1,
                    applied: true
                )
            }

    /// Rows the vanilla pages do not have. The menu shows none of them.
    private static let opensky: [PlayerSettingDefinition] = [
        row("opensky.compass", .opensky, .toggle, "Compass", 1, applied: true),
        row(
            "opensky.startAtTitleScreen",
            .opensky,
            .toggle,
            "Start at title screen",
            0,
            applied: true
        )
    ]
}
