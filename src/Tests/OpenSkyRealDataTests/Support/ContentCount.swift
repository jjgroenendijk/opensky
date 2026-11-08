/// Counts of install content, such as records or scripts, move a little with each game
/// update. A parser that drops or doubles entries moves them far, so a test checks a band.
nonisolated enum ContentCount {
    /// Within 50% to 150% of the measured baseline.
    static func isNear(_ value: Int, _ baseline: Int) -> Bool {
        value * 2 >= baseline && value * 2 <= baseline * 3
    }
}
