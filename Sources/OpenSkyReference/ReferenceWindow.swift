// Which on-screen window is the reference game. Wine names its processes after itself
// or after the Windows program, so both count; the biggest such window wins over Steam's.

import Foundation

nonisolated public struct ReferenceWindowInfo: Equatable, Sendable {
    public var id: UInt32
    public var ownerName: String
    public var layer: Int
    public var width: Double
    public var height: Double

    public init(id: UInt32, ownerName: String, layer: Int, width: Double, height: Double) {
        self.id = id
        self.ownerName = ownerName
        self.layer = layer
        self.width = width
        self.height = height
    }
}

nonisolated public enum ReferenceWindow {
    static let ownerHints = ["wine", "skyrim"]

    public static func pick(_ windows: [ReferenceWindowInfo]) -> ReferenceWindowInfo? {
        windows
            .filter { window in
                window.layer == 0
                    && ownerHints.contains { window.ownerName.lowercased().contains($0) }
            }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    /// `appmanifest_489830.acf` two folders above a Steam game folder.
    public static func manifest(forInstall install: URL) -> URL {
        install.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "appmanifest_\(ReferencePrefix.appID).acf")
    }
}
