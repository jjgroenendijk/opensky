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
            "Quest.Alias.declaredItemCount",
            "StoryManagerNode.declaredQuestCount"
        ],
        .layout: [
            "CameraShot.dataSize",
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
            "WaterDetails.unusedMaterialID",
            "WeatherSky.legacyCloudSpeeds"
        ]
    ]
}
