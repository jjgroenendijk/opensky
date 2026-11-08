import Foundation

nonisolated public struct SystemMenuControlSnapshot: Equatable, Sendable {
    /// Read-only here: Settings (Cmd+,) owns changing the data root.
    public let dataRootPath: String?
    public let dataRootSource: String?
    public let audioEnabled: Bool

    /// Vanilla presentation layer.
    public let movieEnabled: Bool
    public let page: SystemMenuPageSnapshot

    public init(
        dataRootPath: String?,
        dataRootSource: String?,
        audioEnabled: Bool,
        movieEnabled: Bool,
        page: SystemMenuPageSnapshot
    ) {
        self.dataRootPath = dataRootPath
        self.dataRootSource = dataRootSource
        self.audioEnabled = audioEnabled
        self.movieEnabled = movieEnabled
        self.page = page
    }
}
