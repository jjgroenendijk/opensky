// Record fields the game does not use while it runs: the record's own form ID, list counts,
// layout markers, Creation Kit data, and fields older versions wrote. The gap report counts
// them as done (docs/formats/unused-record-data.md).

import Foundation

nonisolated public enum RecordDataUnusedReason: String, CaseIterable, Sendable {
    /// The record's own form ID or type, copied from its header. Stores key records by it.
    case recordIdentity
    /// The count of the list that follows it. The list itself holds the data.
    case listCount
    /// A version, a size, or an empty marker that says how the bytes after it are laid out.
    case layout
    /// Data only the Creation Kit shows or keeps, such as notes and editor colours.
    case editorOnly
    /// A field from an older version of the format that the game no longer reads.
    case legacy
    /// The game reads it and throws it away, or keeps it where no rule reads it.
    case droppedAtLoad
    /// The game keeps it, but the only rule that reads it never runs.
    case noEffect
}

nonisolated public enum RecordDataUnused: Sendable {
    /// Why the game does not use `field`, keyed `Type.Nested.field`, or nil when it does.
    public static func reason(forField field: String) -> RecordDataUnusedReason? {
        if let reason = fields[field] {
            return reason
        }
        let parts = field.split(separator: ".")
        return parts.count == 2 && parts[1] == "formID" ? .recordIdentity : nil
    }

    /// Why the game does not use `bit` of the option set `type`, such as `TopicInfo.Flags`.
    public static func reason(forBit bit: UInt64, of type: String) -> RecordDataUnusedReason? {
        bits[type]?[bit]
    }

    /// Why the game does not use enum case `name` of `type`, such as `TopicInfo.FavorLevel`.
    public static func reason(forCase name: String, of type: String) -> RecordDataUnusedReason? {
        cases["\(type).\(name)"]
    }

    static let bits: [String: [UInt64: RecordDataUnusedReason]] = [
        "TopicInfo.Flags": [0x1000: .droppedAtLoad, 0x4000: .noEffect]
    ]

    static let cases: [String: RecordDataUnusedReason] = [
        "TopicInfo.FavorLevel.small": .noEffect,
        "TopicInfo.FavorLevel.medium": .noEffect,
        "TopicInfo.FavorLevel.large": .noEffect
    ]

    static let fields: [String: RecordDataUnusedReason] = names.reduce(into: [:]) {
        for name in $1.value {
            $0[name] = $1.key
        }
    }

    static let names: [RecordDataUnusedReason: [String]] = [
        .recordIdentity: ["LeveledList.recordType", "PlacedProjectile.recordType"],
        .listCount: [
            "CellExtras.waterVelocityCount",
            "CollisionLayer.interactablesCount",
            "ConstructibleObject.declaredComponentCount",
            "Container.declaredEntryCount",
            "DialogueTopic.declaredInfoCount",
            "IdleMarker.declaredIdleCount",
            "KeywordList.declaredCount",
            "LeveledList.declaredEntryCount",
            "MusicTrack.declaredConditionCount",
            "PackageDetails.IdleAnimations.declaredCount",
            "PlacedReferenceDetails.Room.linkedRoomCount",
            "PlacedReferenceDetails.waterVelocityCount",
            "PluginHeader.interiorCellCount",
            "Quest.Alias.declaredItemCount",
            "StoryManagerNode.declaredQuestCount"
        ],
        .layout: [
            "CameraShot.dataSize",
            "WorldspaceDetails.offsets",
            "PlacedReferenceDetails.Patrol.hasScriptMarker",
            "ScriptData.objectFormat",
            "ScriptData.version"
        ],
        .editorOnly: [
            "DialogueView.showsAllText",
            "DialogueView.topicType",
            "PluginHeader.intv",
            "Quest.nextAliasID",
            "Quest.objectWindowFilter",
            "ScenePhase.editorWidth",
            "TopicInfo.Response.edits",
            "TopicInfo.Response.scriptNotes"
        ],
        .legacy: [
            "ActorAIData.unknown",
            "CellExtras.legacyFlags",
            "DialogueTopic.legacySubtype",
            "PluginHeader.masterData",
            "SoundMarker.legacyFNAM",
            "SoundMarker.legacySNDD",
            "TopicInfo.LegacyScriptBlock.header",
            "TopicInfo.LegacyScriptBlock.quest",
            "TopicInfo.legacyDialogueTab",
            "TopicInfo.legacyScriptBlocks",
            "WaterDetails.unusedMaterialID"
        ],
        .droppedAtLoad: [
            "RaceProperties.unknown",
            "RaceProperties.weight",
            "AcousticSpace.editorID",
            "ArtObject.bounds",
            "Debris.editorID",
            "DualCastData.bounds",
            "Enchantment.bounds",
            "Footstep.editorID",
            "Grass.bounds",
            "Grass.editorID",
            "Impact.editorID",
            "LeveledList.bounds",
            "LightingTemplate.editorID",
            "CellExtras.maxHeightData",
            "Location.editorColor",
            "MaterialObject.editorID",
            "Outfit.editorID",
            "PlacedReferenceDetails.LightData.unknown",
            "PlacedReferenceDetails.boundHalfExtents",
            "PlacedReferenceDetails.editorID",
            "PlacedReferenceDetails.headTrackingWeight",
            "PlacedReferenceDetails.isIgnoredBySandbox",
            "PlacedReferenceDetails.isMultiBoundPrimitive",
            "PlacedReferenceDetails.occlusionPlane",
            "Region.mapColor",
            "Scene.lastActionIndex",
            "SoundOutputModel.editorID",
            "TextureSet.bounds",
            "TextureSet.editorID",
            "TopicInfo.editorID",
            "VolumetricLighting.editorID",
            "WaterType.editorID",
            "WorldspaceDetails.hdLODDiffuseTexture",
            "WorldspaceDetails.hdLODNormalTexture"
        ],
        .noEffect: ["PlacedReferenceDetails.LightData.endDistanceCap", "TopicInfo.favorLevel"]
    ]
}
