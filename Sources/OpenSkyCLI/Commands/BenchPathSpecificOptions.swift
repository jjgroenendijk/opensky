// The `bench` options that only one of the two paths, the cell render or the
// walk path, accepts.

import OpenSkyCLIArguments

struct BenchPathSpecificOptions {
    let frames: String?
    let footprintCapMB: String?
    let collisionBuildBudgetMS: String?
    let actorBuildBudgetMS: String?
    let animationUpdateBudgetMS: String?
    let shadowUpdateBudgetMS: String?
    let scriptUpdateBudgetMS: String?

    init(arguments: BenchBudgetOptions, walkPath: Bool) throws {
        frames = arguments.frames
        footprintCapMB = arguments.footprintCapMb
        collisionBuildBudgetMS = arguments.collisionBuildBudgetMs
        actorBuildBudgetMS = arguments.actorBuildBudgetMs
        animationUpdateBudgetMS = arguments.animationBudgetMs
        shadowUpdateBudgetMS = arguments.shadowBudgetMs
        scriptUpdateBudgetMS = arguments.scriptBudgetMs

        guard walkPath else { return }
        if let option = arguments.given.first(where: { $0.value != nil }) {
            throw CLIError.usage("\(option.flag) is not supported with --walk-path")
        }
    }
}
