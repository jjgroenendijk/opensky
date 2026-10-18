// The measured AS2 contract of `Interface\trainingmenu.swf`. The engine writes the card's
// text fields under `/TrainingMenuObj` and sets the skill meter; the buttons call `Train`
// and `Exit`. See docs/engine/training.md#training-menu.

import Foundation
import OpenSkyFormatsSWF

/// What the training card shows for one trainer.
nonisolated public struct TrainingCard: Equatable, Sendable {
    public var skillName: String
    public var skillLevel: Int
    /// 0 to 1 towards the next skill level.
    public var skillProgress: Float
    public var trainerName: String
    public var trainerMaximum: Int
    public var sessions: Int
    public var sessionsPerLevel: Int
    public var cost: Int
    public var gold: Int

    public init(
        skill: (name: String, level: Int, progress: Float),
        trainer: (name: String, maximum: Int),
        sessions: (done: Int, perLevel: Int),
        cost: Int,
        gold: Int
    ) {
        skillName = skill.name
        skillLevel = skill.level
        skillProgress = skill.progress
        trainerName = trainer.name
        trainerMaximum = trainer.maximum
        self.sessions = sessions.done
        sessionsPerLevel = sessions.perLevel
        self.cost = cost
        self.gold = gold
    }

    /// The card's lines, in the movie's field order. The wording is OpenSky's.
    public var lines: [String] {
        [
            "\(skillName) \(skillLevel)",
            "\(trainerName) trains up to \(trainerMaximum)",
            "Trained \(sessions) of \(sessionsPerLevel) times this level",
            "Cost: \(cost)",
            "Gold: \(gold)"
        ]
    }
}

/// A call the training movie makes.
nonisolated public enum TrainingMovieEvent: Equatable, Sendable {
    case train
    case exit
}

nonisolated public enum TrainingMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\trainingmenu.swf"
    public static let menuPath = "/TrainingMenuObj"
    static let fieldNames = [
        "SkillName", "TrainerSkill", "TimesTrained", "TrainCost", "CurrentGold"
    ]

    public static func prepare(
        runtime: SWFMovieRuntime,
        onEvent: @escaping @MainActor @Sendable (TrainingMovieEvent) -> Void
    ) {
        runtime.registerHostFunction("PlaySound") { _ in .undefined }
        runtime.registerHostFunction("Train") { _ in
            MainActor.assumeIsolated { onEvent(.train) }
            return .undefined
        }
        runtime.registerHostFunction("Exit") { _ in
            MainActor.assumeIsolated { onEvent(.exit) }
            return .undefined
        }
    }

    /// The root `InitExtensions` passes the platform to `TrainingMenuObj.SetPlatform`.
    public static func activate(runtime: SWFMovieRuntime) {
        runtime.callMovie(
            "InitExtensions",
            arguments: [.number(SystemMenuMovieBridge.pcPlatform), .boolean(false)]
        )
    }

    public static func publish(_ card: TrainingCard, runtime: SWFMovieRuntime) {
        for (name, line) in zip(fieldNames, card.lines) {
            MenuMovieText.set(line, atPath: "\(menuPath)/\(name)", runtime: runtime)
        }
        MenuMovieText.callMeter(
            "SetPercent", meter: "SkillMeter", ofPath: menuPath,
            percent: Double(card.skillProgress) * 100, runtime: runtime
        )
    }
}
