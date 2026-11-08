import Foundation
public import OpenSkyDialogueInterface
import OpenSkyFormatsCore
public import OpenSkyGameData

nonisolated extension SpeechTimerSettings {
    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        let fields: [(String, WritableKeyPath<Self, Float>)] = [
            ("fGameplayVoiceFilePadding", \.voiceFilePadding),
            ("fAIForceGreetingTimer", \.forceGreetingSeconds),
            ("fAIGreetingTimer", \.greetingSeconds),
            ("fAIExclusiveGreetingTimer", \.exclusiveGreetingSeconds),
            ("fAIMinGreetingDistance", \.greetingDistance),
            ("fAIInDialogueModeWithPlayerDistance", \.playerCommentDistance),
            ("fCombatDialogueAttackMinElapsedTime", \.attackLineMinSeconds),
            ("fCombatDialogueAttackMaxElapsedTime", \.attackLineMaxSeconds),
            ("fCombatDialogueTauntMinElapsedTime", \.tauntMinSeconds),
            ("fCombatDialogueTauntMaxElapsedTime", \.tauntMaxSeconds),
            ("fCombatSpeakAttackChance", \.attackLineChance),
            ("fCombatSpeakHitChance", \.hitLineChance),
            ("fCombatSpeakTauntChance", \.tauntChance),
            ("fCombatSpeakHitThreshold", \.hitLineThreshold),
            ("fIdleChatterCommentTimer", \.idleChatterMinSeconds),
            ("fIdleChatterCommentTimerMax", \.idleChatterMaxSeconds),
            ("fCommentOnPlayerActionsTimer", \.playerActionCommentSeconds),
            ("fCommentOnPlayerKnockingThings", \.knockOverCommentSeconds),
            ("fBumpReactionSmallWaitTimer", \.bumpLineSeconds),
            ("fSpeechDelay", \.speechDelay),
            ("fDialogSpeechDelaySeconds", \.silentLineMinSeconds),
            ("fSubtitleSpeechDelay", \.silentLineMaxSeconds),
            ("fRandomSceneAgainMinTime", \.sceneRepeatMinSeconds),
            ("fRandomSceneAgainMaxTime", \.sceneRepeatMaxSeconds)
        ]
        for (editorID, keyPath) in fields {
            store.read(editorID, into: &settings, keyPath)
        }
        return settings
    }
}
