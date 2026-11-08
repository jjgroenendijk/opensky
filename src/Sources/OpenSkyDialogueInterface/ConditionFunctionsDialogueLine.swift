// Condition functions over the line an actor says to the player, indices from xEdit
// wbDefinitionsTES5.pas: 141 `IsTalking`, 123 `IsGreetingPlayer`, 434
// `GetDialogueEmotion`, and 435 `GetDialogueEmotionValue`.
// See docs/engine/condition-functions-world.md#dialogue-lines.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

nonisolated extension ConditionFunctions {
    static func installDialogueLine(_ registry: inout ConditionFunctionRegistry) {
        registry.register(lineRead(141, "IsTalking") { _ in 1 })
        registry.register(lineRead(123, "IsGreetingPlayer") { isTrue($0.isGreeting) })
        registry.register(lineRead(434, "GetDialogueEmotion") { Float($0.emotion) })
        registry.register(lineRead(435, "GetDialogueEmotionValue") { Float($0.emotionValue) })
    }

    private static func lineRead(
        _ index: UInt16, _ name: String,
        _ read: @escaping @Sendable (DialogueSpokenLine) -> Float
    ) -> ConditionFunction {
        ConditionFunction(index: index, name: name) { call in
            let dialogue = call.context.dialogue
            guard dialogue.isAvailable else { return .failure(.unavailableDialogue) }
            return call.referenceKey().map { key in
                guard let line = dialogue.line, line.speaker == key else { return 0 }
                return read(line)
            }
        }
    }
}
