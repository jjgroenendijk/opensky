// The `bench` options that only one of the two paths, the cell render or the
// walk path, accepts.

struct BenchPathSpecificOptions {
    let frames: String?
    let footprintCapMB: String?
    let collisionBuildBudgetMS: String?
    let actorBuildBudgetMS: String?
    let animationUpdateBudgetMS: String?
    let shadowUpdateBudgetMS: String?
    let scriptUpdateBudgetMS: String?

    init(scanner: inout ArgumentScanner, walkPath: Bool) throws {
        frames = try scanner.option("--frames")
        footprintCapMB = try scanner.option("--footprint-cap-mb")
        collisionBuildBudgetMS = try scanner.option("--collision-build-budget-ms")
        actorBuildBudgetMS = try scanner.option("--actor-build-budget-ms")
        animationUpdateBudgetMS = try scanner.option("--animation-budget-ms")
        shadowUpdateBudgetMS = try scanner.option("--shadow-budget-ms")
        scriptUpdateBudgetMS = try scanner.option("--script-budget-ms")

        guard walkPath else { return }
        let options = [
            ("--frames", frames),
            ("--footprint-cap-mb", footprintCapMB),
            ("--collision-build-budget-ms", collisionBuildBudgetMS),
            ("--actor-build-budget-ms", actorBuildBudgetMS),
            ("--animation-budget-ms", animationUpdateBudgetMS),
            ("--shadow-budget-ms", shadowUpdateBudgetMS),
            ("--script-budget-ms", scriptUpdateBudgetMS)
        ]
        if let option = options.first(where: { $0.1 != nil }) {
            throw CLIError.usage("\(option.0) is not supported with --walk-path")
        }
    }
}
