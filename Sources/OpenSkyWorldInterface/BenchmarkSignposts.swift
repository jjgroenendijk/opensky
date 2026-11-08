/// What the overlay shows about the running tour.
nonisolated public struct BenchmarkTourSnapshot: Equatable, Sendable {
    public enum Step: String, Sendable {
        case loading, arriving, settling, measuring
    }

    public var sceneNumber: Int
    public var sceneCount: Int
    public var title: String
    public var step: Step
    /// Of the current step, from 0 to 1.
    public var progress: Double
    public var fps: Double?

    public init(
        sceneNumber: Int,
        sceneCount: Int,
        title: String,
        step: Step,
        progress: Double,
        fps: Double? = nil
    ) {
        self.sceneNumber = sceneNumber
        self.sceneCount = sceneCount
        self.title = title
        self.step = step
        self.progress = progress
        self.fps = fps
    }
}
