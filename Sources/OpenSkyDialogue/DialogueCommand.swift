// What the dialogue coordinator asks the app to do. See docs/engine/coordinators.md.

import OpenSkyFormatsESM
import simd

/// One change to the world outside the dialogue domain.
nonisolated public enum DialogueCommand: Equatable, Sendable {
    case suspendPackage(ReferenceKey)
    /// Selects a package again for the world as it is now.
    case resumePackage(ReferenceKey)
    case stopActor(ReferenceKey)
    case faceActor(ReferenceKey, towards: SIMD3<Float>)
    case releaseFacing(ReferenceKey)
    /// The player said a line that wins a speech challenge against the speaker.
    case speechChallengeWon(SpeechChallenge, speaker: ReferenceKey)
    /// The speaker said a line to the player, which `GetTalkedToPC` reads.
    case spokeToPlayer(ReferenceKey)
}

/// An answer and the commands the app runs with it.
nonisolated public struct DialogueResult<Value> {
    public let value: Value
    public let commands: [DialogueCommand]

    public init(_ value: Value, commands: [DialogueCommand] = []) {
        self.value = value
        self.commands = commands
    }
}

extension DialogueResult: Equatable where Value: Equatable {}
extension DialogueResult: Sendable where Value: Sendable {}
